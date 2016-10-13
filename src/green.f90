!------------------------------------------------------------------------------
!
! This file is part of the Sternheimer-GW code.
! 
! Copyright (C) 2010 - 2016 
! Henry Lambert, Martin Schlipf, and Feliciano Giustino
!
! Sternheimer-GW is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! Sternheimer-GW is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with Sternheimer-GW. If not, see
! http://www.gnu.org/licenses/gpl.html .
!
!------------------------------------------------------------------------------ 
!> Wraps the routines used to evaluate the Green's function of the system.
MODULE green_module

  IMPLICIT NONE

  PUBLIC green_function, green_prepare, green_nonanalytic
  PRIVATE

CONTAINS

  !> Prepare the QE global modules, so that the Green's function can be evaluated.
  !!
  !! Because QE stores some information in global modules, we need to initialize
  !! those quantities appropriatly so that the function calls work as intented.
  !!
  SUBROUTINE green_prepare(ikq, gcutcorr, map, num_g, occupation, eval, evec)

    USE buffers,           ONLY: get_buffer
    USE control_gw,        ONLY: nbnd_occ
    USE kinds,             ONLY: dp
    USE klist,             ONLY: igk_k, xk, ngk
    USE reorder_mod,       ONLY: create_map
    USE units_gw,          ONLY: lrwfc, iuwfc
    USE uspp,              ONLY: vkb
    USE wvfct,             ONLY: current_k, et, npwx

    !> The index of the point k - q
    INTEGER,  INTENT(IN)  :: ikq

    !> The G-vector cutoff for the correlation.
    INTEGER,  INTENT(IN)  :: gcutcorr

    !> The map from G-vectors at current k to global array.
    INTEGER,  INTENT(OUT), ALLOCATABLE :: map(:)

    !> The total number of G-vectors at this k-point
    INTEGER,  INTENT(OUT) :: num_g

    !> The occupation of the eigenstates
    REAL(dp),    INTENT(OUT), ALLOCATABLE :: occupation(:)

    !> eigenvalue of all bands at k - q
    COMPLEX(dp), INTENT(OUT), ALLOCATABLE :: eval(:)

    !> eigenvector of all bands at k - q
    COMPLEX(dp), INTENT(OUT), ALLOCATABLE :: evec(:,:)

    !> helper for the number of occupied bands
    INTEGER num_band_occ

    !> number of G-vectors for correlation
    INTEGER num_g_corr

    !> temporary copy of the map array
    INTEGER, ALLOCATABLE :: map_(:)

    !> complex constant of 0
    COMPLEX(dp), PARAMETER :: zero = CMPLX(0.0_dp, 0.0_dp, KIND=dp)

    !> constant of 1 indicating a fully occupied state
    REAL(dp), PARAMETER :: occupied = 1.0_dp

    !> constant of 0 indicating an unoccupied state
    REAL(dp), PARAMETER :: unoccupied = 0.0_dp

    current_k = ikq

    !
    ! create the output map array
    !
    ! count the number of G vectors used for correlation
    num_g = ngk(ikq)
    num_g_corr = COUNT((igk_k(:,ikq) > 0) .AND. (igk_k(:,ikq) <= gcutcorr))

    ! allocate the array
    ALLOCATE(map(num_g_corr))
    ALLOCATE(map_(SIZE(igk_k, 1)))

    ! create the map and copy to result array
    map_ = create_map(igk_k(:,ikq), gcutcorr)
    map = map_(:gcutcorr)

    ! free memory
    DEALLOCATE(map_)

    !
    ! call necessary global initialize routines
    !
    ! evaluate kinetic energy
    CALL g2_kin(ikq)

    ! initialize PP projectors
    CALL init_us_2(num_g, igk_k(:,ikq), xk(:,ikq), vkb)

    !
    ! read eigenvalue and eigenvector and set the occupation
    !
    ALLOCATE(occupation(SIZE(et, 1)))
    ALLOCATE(eval(SIZE(et, 1)))
    ALLOCATE(evec(npwx, SIZE(et, 1)))

    ! set the occupation of the eigenstates
    num_band_occ = nbnd_occ(ikq)
    occupation(:num_band_occ)     = occupied
    occupation(num_band_occ + 1:) = unoccupied

    ! set eigenvalue (complex to allow shifting it into the complex plane)
    eval = CMPLX(et(:,ikq), 0.0_dp, KIND=dp)

    ! read wave function
    CALL get_buffer(evec, lrwfc, iuwfc, ikq)
    evec(num_g + 1:, :) = zero

  END SUBROUTINE green_prepare

  !> Evaluate the Green's function of the system.
  !!
  !! We solve the linear equation in reciprocal space to obtain the Green's
  !! function \f$G\f$
  !! \f{equation}{
  !!   (H_k(G') - \omega) G_k(G,G',\omega) = -\delta_{G,G'}~,
  !! \f}
  !! where \f$H_k\f$ is the Hamiltonian at a certain k-point, \f$\omega\f$ is
  !! the frequency, and \f$\delta_{G,G'}\f$ is the Kronecker delta.
  !!
  SUBROUTINE green_function(comm, multishift, lmax, threshold, map, num_g, omega, green, debug)

    USE bicgstab_module,      ONLY: bicgstab
    USE debug_module,         ONLY: debug_type, debug_set
    USE kinds,                ONLY: dp
    USE linear_solver_module, ONLY: linear_solver, linear_solver_config
    USE parallel_module,      ONLY: parallel_task, mp_allgatherv
    USE timing_module,        ONLY: time_green

    !> Parallelize the calculation over this communicator
    INTEGER,     INTENT(IN)  :: comm

    !> Use the multishift solver to determine the Green's function
    LOGICAL,     INTENT(IN)  :: multishift

    !> Depth of the GMRES part of the BiCGstab(l) algorithm.
    INTEGER,     INTENT(IN)  :: lmax

    !> Threshold for the convergence of the linear system.
    REAL(dp),    INTENT(IN)  :: threshold

    !> The reverse list from global G vector order to current k-point.
    !! Generate this by a call to create_map in reorder.
    !! @note this should be reduced to the correlation cutoff
    INTEGER,     INTENT(IN)  :: map(:)

    !> The number of G-vectors at the k-point.
    INTEGER,     INTENT(IN)  :: num_g

    !> The list of frequencies for which the Green's function is evaluated.
    COMPLEX(dp), INTENT(IN)  :: omega(:)

    !> The Green's function of the system.
    COMPLEX(dp), INTENT(OUT) :: green(:,:,:)

    !> the debug configuration of the calculation
    TYPE(debug_type), INTENT(IN) :: debug

    !> distribution of the tasks over the process grid
    INTEGER,     ALLOCATABLE :: num_task(:)

    !> The right hand side of the linear equation
    COMPLEX(dp), ALLOCATABLE :: bb(:)

    !> Helper array storing the result of the linear equation
    COMPLEX(dp), ALLOCATABLE :: green_part(:,:)

    !> Green's function that is gathered across the processes
    COMPLEX(dp), ALLOCATABLE :: green_comm(:,:,:)

    !> The number of frequencies.
    INTEGER num_freq

    !> The number of G-vectors for the correlation
    INTEGER num_g_corr

    !> First and last G-vector done on this process
    INTEGER ig_start, ig_stop

    !> loop variable for G loop
    INTEGER ig, igp

    !> loop over frequencies
    INTEGER ifreq

    !> check error in array allocation
    INTEGER ierr

    !> the configuration for the solver in the non-multishift case
    TYPE(linear_solver_config) config

    !> complex zero
    COMPLEX(dp), PARAMETER :: zero = 0.0_dp

    !> complex one
    COMPLEX(dp), PARAMETER :: one = 1.0_dp

    CALL start_clock(time_green)

    ! determine helper variables
    num_g_corr = SIZE(map)
    num_freq = SIZE(omega)

    ! sanity test of the input
    IF (SIZE(green, 1) < num_g_corr) &
      CALL errore(__FILE__, "first dimension of Green's functions to small", 1)
    IF (SIZE(green, 2) < num_g_corr) &
      CALL errore(__FILE__, "second dimension of Green's function to small", 1)
    IF (SIZE(green, 3) /= num_freq) &
      CALL errore(__FILE__, "Green's function and omega are inconsistent", 1)

    ! allocate array for the right hand side
    ALLOCATE(bb(num_g), STAT = ierr)
    CALL errore(__FILE__, "could not allocate bb", ierr)

    ! initialize array
    green = zero

    ! allocate array for result of the linear system
    ALLOCATE(green_part(num_g, num_freq), STAT = ierr)
    CALL errore(__FILE__, "could not allocate green_part", ierr)

    ! parallelize over communicator
    CALL parallel_task(comm, num_g_corr, ig_start, ig_stop, num_task)

    ! allocate array to gather Green's function
    ALLOCATE(green_comm(num_g_corr, num_freq, num_g_corr), STAT = ierr)
    CALL errore(__FILE__, "could not allocate green_comm", ierr)

    ! loop over all G-vectors
    DO ig = ig_start, ig_stop

      ! set right-hand side
      bb = zero
      bb(map(ig)) = -one

      ! if multishift is set, we solve all frequencies at once
      IF (multishift) THEN

        ! solve the linear system
        CALL bicgstab(lmax, threshold, green_operator, bb, -omega, green_part)

      ! without multishift, we solve every frequency separately
      ELSE

        ! solve the linear system reusing the Krylov subspace
        config%threshold = threshold
        CALL linear_solver(config, green_operator, bb, -omega, green_part)

      END IF

      ! copy from temporary array to communicated array
      green_comm(:, :, ig) = green_part(map, :)

      ! debug the solver
      IF (debug_set) CALL green_solver_debug(omega, threshold, bb, green_part, debug)

    END DO ! ig

    ! free memory
    DEALLOCATE(bb)
    DEALLOCATE(green_part)

    ! gather the result from all processes
    CALL mp_allgatherv(comm, num_task, green_comm)

    ! reorder into result array
    DO ig = 1, num_g_corr
      DO igp = 1, num_g_corr
        green(ig, igp, :) = green_comm(igp, :, ig)
      END DO ! igp
    END DO ! ig

    DEALLOCATE(num_task)
    DEALLOCATE(green_comm)

    CALL stop_clock(time_green)

  END SUBROUTINE green_function

  !> Add the nonanalytic part of the Green's function.
  !!
  !! For real space frequency integration, we split a nonanalytic part of the
  !! Green's function so that the resulting analytic part has no poles above
  !! the real axis. The nonanalytic part is given as
  !! \f{equation}{
  !!   G_{\text{N}}(G, G', \omega) = 2 \pi i \sum_{n} f_n
  !!   \delta(\omega - \epsilon_{n}) u_{n}^\ast(G) u_{n}(G')
  !! \f}
  !! where the \f$u_{n}(G)\f$ are the eigenvectors. Note that the sum runs over
  !! the occupied states only, which is controlled by the occupation factor
  !! \f$f_n\f$.
  !! We approximate the \f$\delta\f$ function by a Cauchy-Lorentz distribution
  !! \f{equation}{
  !!   \delta(\omega) \approx \frac{\eta}{\pi(\omega^2 + \eta^2)}
  !! \f}
  SUBROUTINE green_nonanalytic(map, freq, occupation, eval, evec, green)

    USE constants,     ONLY: pi, tpi
    USE kinds,         ONLY: dp
    USE timing_module, ONLY: time_green

    !> The reverse list from global G vector order to current k-point.
    !! Generate this by a call to create_map in reorder.
    !! @note this should be reduced to the correlation cutoff
    INTEGER,     INTENT(IN)    :: map(:)

    !> The frequency points for which the Green's function is evaluated.
    !! @note This is a complex \f$\omega + i \eta\f$
    COMPLEX(dp), INTENT(IN)    :: freq(:)

    !> Occupation \f$f_n\f$ of a certain state.
    REAL(dp),    INTENT(IN)    :: occupation(:)

    !> The eigenvalues \f$\epsilon\f$ for the occupied bands.
    COMPLEX(dp), INTENT(IN)    :: eval(:)

    !> The eigenvectors \f$u_{\text v}(G)\f$ of the occupied bands.
    COMPLEX(dp), INTENT(IN)    :: evec(:,:)

    !> The Green's function - note that the nonanalytic part is added to
    !! whatever is already found in the array.
    COMPLEX(dp), INTENT(INOUT) :: green(:,:,:)

    !> the number of occupied bands
    INTEGER num_band

    !> the number of G vectors at the k-point
    INTEGER num_g

    !> the number of G vectors used for the correlation
    INTEGER num_g_corr

    !> the number of frequency points
    INTEGER num_freq

    !> loop variable for summation over valence bands
    INTEGER iband

    !> loop variable for frequencies
    INTEGER ifreq

    !> loop variable for G and G'
    INTEGER ig, igp

    !> the value of \f$\omega - \epsilon_{\text{v}} + \imag \eta\f$
    COMPLEX(dp) freq_eps

    !> the value of the Lorentzian distribution
    REAL(dp) lorentzian

    !> 2 pi i
    COMPLEX(dp), PARAMETER :: c2PiI = CMPLX(0.0_dp, tpi, KIND=dp)

    CALL start_clock(time_green)

    ! initialize helper variables
    num_band = SIZE(eval)
    num_freq = SIZE(freq)
    num_g    = SIZE(evec, 1)
    num_g_corr = SIZE(map)

    ! sanity check of the input
    IF (SIZE(occupation) /= num_band) &
      CALL errore(__FILE__, "size of occupation and eigenvalue array inconsistent", 1)
    IF (SIZE(evec, 2) /= num_band) &
      CALL errore(__FILE__, "size of eigenvalue and eigenvector inconsistent", 1)
    IF (num_g < num_g_corr) &
      CALL errore(__FILE__, "cannot use more G's for correlation that available", 1)
    IF (SIZE(green, 1) < num_g_corr) &
      CALL errore(__FILE__, "1st dimension of Green's function to small", 1)
    IF (SIZE(green, 2) < num_g_corr) &
      CALL errore(__FILE__, "2nd dimension of Green's function to small", 1)
    IF (SIZE(green, 3) /= num_freq) &
      CALL errore(__FILE__, "3rd dimension of Green's function should be number of frequencies", 1)

    ! loop over frequencies
    DO ifreq = 1, num_freq

      ! loop over bands
      DO iband = 1, num_band

        ! determine omega - epsilon + imag eta
        freq_eps = freq(ifreq) - eval(iband)

        ! determine the value of the Lorentzian
        lorentzian = AIMAG(freq(ifreq)) / (pi * ABS(freq_eps)**2)

        ! loop over G and G'
        DO igp = 1, num_g_corr
          DO ig = 1, num_g_corr

            ! add nonanalytic part to Green's function
            ! 2 pi i f_n u_n*(G) u_n(G') delta
            green(ig, igp, ifreq) = green(ig, igp, ifreq) + c2PiI * occupation(iband) &
              * CONJG(evec(map(ig), iband)) * evec(map(igp), iband) * lorentzian

          END DO ! ig
        END DO ! igp

      END DO ! iband

    END DO ! ifreq

    CALL stop_clock(time_green)

  END SUBROUTINE green_nonanalytic

  !> Wrapper for the linear operator call.
  !!
  !! Sets the necessary additional variables.
  SUBROUTINE green_operator(omega, psi, A_psi)

    USE kinds,            ONLY: dp
    USE linear_op_module, ONLY: linear_op
    USE wvfct,            ONLY: npwx, current_k

    !> The initial shift
    COMPLEX(dp), INTENT(IN)  :: omega

    !> The input vector.
    COMPLEX(dp), INTENT(IN)  :: psi(:)

    !> The operator applied to the vector.
    COMPLEX(dp), INTENT(OUT) :: A_psi(:)

    !> Local copy of omega, because linear_op require arrays.
    COMPLEX(dp) omega_(1)

    !> Local copies of psi and A_psi because linear_op requires arrays.
    COMPLEX(dp), ALLOCATABLE :: psi_(:,:), A_psi_(:,:)

    !> real value of zero
    REAL(dp), PARAMETER :: zero = 0.0_dp

    !> Error code.
    INTEGER ierr

    !> number of G vectors
    INTEGER num_g

    ! determine number of G vectors
    num_g = SIZE(psi)

    !> allocate temporary array
    ALLOCATE(psi_(npwx, 1), A_psi_(npwx, 1), STAT = ierr)
    CALL errore(__FILE__, "could not allocate temporary arrays psi_ and A_psi_", ierr)

    !
    ! initialize helper
    !

    omega_ = omega

    ! zero the elements outside of the definition
    psi_(:num_g, 1) = psi
    psi_(num_g + 1:, 1) = zero

    !
    ! apply the linear operator (H - w) psi
    !
    ! for the Green's function
    ! alpha_pv = 0
    CALL linear_op(current_k, num_g, omega_, zero, psi_, A_psi_)

    ! extract result
    A_psi = A_psi_(:num_g,1)

    ! free memory
    DEALLOCATE(psi_, A_psi_)

  END SUBROUTINE green_operator

  !> This routine writes the Hamiltonian to file in matrix format
  SUBROUTINE green_solver_debug(omega, threshold, bb, green, debug)

    USE debug_module, ONLY: debug_type, test_nan
    USE iotk_module,  ONLY: iotk_free_unit, iotk_index, &
                            iotk_open_write, iotk_write_dat, iotk_close_write
    USE kinds,        ONLY: dp
    USE mp_world,     ONLY: mpime
    USE sleep_module, ONLY: sleep, two_min

    !> The initial shift
    COMPLEX(dp), INTENT(IN) :: omega(:)

    !> The target threshold of the linear solver
    REAL(dp),    INTENT(IN) :: threshold

    !> the right hand side of the linear equation
    COMPLEX(dp), INTENT(IN) :: bb(:)

    !> the calculated Green's function
    COMPLEX(dp), INTENT(IN) :: green(:,:)

    !> the configuration for the debug run
    TYPE(debug_type), INTENT(IN) :: debug

    !> this flag will be set if an extensive test is necessary
    LOGICAL extensive_test

    !> the number of G vectors
    INTEGER num_g

    !> counter om the G vectors
    INTEGER ig

    !> the number of frequencies
    INTEGER num_freq

    !> counter on the number of frequencies
    INTEGER ifreq

    !> unit for file I/O
    INTEGER iunit

    !> residual error of the linear operator
    REAL(dp) residual

    !> work array for the check of the linear operator
    COMPLEX(dp), ALLOCATABLE :: work(:)

    !> the full Hamiltonian
    COMPLEX(dp), ALLOCATABLE :: hamil(:, :)

    !> complex constant of 0
    COMPLEX(dp), PARAMETER :: zero = CMPLX(0.0_dp, 0.0_dp, KIND=dp)

    !> complex constant of 1
    COMPLEX(dp), PARAMETER :: one = CMPLX(1.0_dp, 0.0_dp, KIND=dp)

    !> complex constant of minus 1
    COMPLEX(dp), PARAMETER :: minus_one = CMPLX(-1.0_dp, 0.0_dp, KIND=dp)

    !> LAPACK function to evaluate the 2-norm
    REAL(dp), EXTERNAL :: DNRM2

    ! trivial case - do not debug this option
    IF (.NOT.debug%solver_green) RETURN

    !
    ! sanity test of the input
    !
    num_g = SIZE(bb)
    num_freq = SIZE(omega)
    IF (SIZE(green, 1) /= num_g) &
      CALL errore(__FILE__, "Green's function has incorrect first dimension", 1)
    IF (SIZE(green, 2) /= num_freq) &
      CALL errore(__FILE__, "Green's function has incorrect second dimension", 1)

    !
    ! check if there is anything that requires an extensive test
    !
    extensive_test = ANY(test_nan(green))
    !
    IF (extensive_test) THEN
      !
      WRITE(debug%note, *) 'debug green_solver: NaN found'
      !
    ELSE
      ! if an extensive test is already necessary, we don't need to do the
      ! expensive test whether (H - w) G = -delta is fulfilled
      !
      ALLOCATE(work(num_g))
      !
      ! test all frequencies
      DO ifreq = 1, num_freq
        !
        ! evaluate work = (H - w) G
        CALL green_operator(-omega(ifreq), green(:, ifreq), work)
        !
        ! work = (H - w) G - bb (should be ~ 0)
        CALL ZAXPY(num_g, minus_one, bb, 1, work, 1)
        !
        ! determine the residual = sum(|work|**2) (note: factor 2 for complex)
        residual = DNRM2(2 * num_g, work, 1)
        !
        ! if residual is not of same order of magnitude as threshold we may want extensive test
        extensive_test = residual > 10.0_dp * threshold
        !
        IF (extensive_test) THEN
          WRITE(debug%note, *) 'debug green_solver: failed', residual
          EXIT
        END IF
        !
      END DO ! ifreq
      !
      DEALLOCATE(work)
      !
    END IF ! check if (H - w) G = -delta

    !
    ! prepare the extensive test
    !
    IF (.NOT.extensive_test) RETURN
    !
    WRITE(debug%note, *) 'extensive test necessary'
    !
    ! allocate work array and Hamiltonian
    ALLOCATE(work(num_g))
    ALLOCATE(hamil(num_g, num_g))

    !
    ! generate the full Hamiltonian
    !
    DO ig = 1, num_g
      !
      ! initialize a single element of work to 1
      work     = zero
      work(ig) = one
      !
      ! evaluate one column of the Hamiltonian
      CALL green_operator(zero, work, hamil(:, ig))
      !
    END DO ! ig

    !
    ! write everything to file
    !
    CALL iotk_free_unit(iunit)
    CALL iotk_open_write(iunit, 'green_solver' // TRIM(iotk_index(mpime)) // '.xml', &
                         binary = .TRUE., root = 'LINEAR_PROBLEM')
    CALL iotk_write_dat(iunit, 'DIMENSION', num_g)
    CALL iotk_write_dat(iunit, 'NUMBER_SHIFT', num_freq)
    CALL iotk_write_dat(iunit, 'LIST_SHIFT', omega)
    CALL iotk_write_dat(iunit, 'LINEAR_OPERATOR', hamil)
    CALL iotk_write_dat(iunit, 'RIGHT_HAND_SIDE', bb)
    CALL iotk_write_dat(iunit, 'INCORRECT_SOLUTION', green)
    CALL iotk_close_write(iunit)
    
    !
    ! finish extensive test - stop calculation after short buffer period
    !
    WRITE(debug%note, *) 'linear problem written to file'
    !
    ! wait for two minutes before stopping so that other processors may reach this point
    ifreq = sleep(two_min)
    !
    CALL errore(__FILE__, "linear solver for Green's function did not pass a test", 1)

  END SUBROUTINE green_solver_debug

END MODULE green_module
