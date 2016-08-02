!------------------------------------------------------------------------------
!
! This file is part of the Sternheimer-GW code.
! Parts of this file are taken from the Quantum ESPRESSO software
! P. Giannozzi, et al, J. Phys.: Condens. Matter, 21, 395502 (2009)
!
! Copyright (C) 2010 - 2016 Quantum ESPRESSO group,
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
!> This module contains the iterative and the direct solver to determine the
!! screened Coulomb interaction.
!!
!! The purpose is to contain the common parts of the solvers in a single routine to
!! avoid code duplication as much as possible. This module is developed starting
!! from solve_linter of the PHonon package.
!------------------------------------------------------------------------------
MODULE solve_module

  IMPLICIT NONE

CONTAINS

!> Driver routine for the solution of the linear system.
!!
!! It defines the change of the wavefunction due to a perturbing potential
!! parameterized in r and iw, i.e. \f$v_{r, iw} (r')\f$
!! Currently symmetrized in terms of mode etc. Might need to strip this out
!! and check PW for how it stores/symmetrizes charge densities.
!!
!! This routine performs the following tasks
!! 1. computes the bare potential term Delta V | psi > 
!! 2. adds to it the screening term Delta V_{SCF} | psi >
!! 3. applies P_c^+ (orthogonalization to valence states)
!! 4. calls c_bi_cgsolve_all to solve the linear system
!! 5. computes Delta rho, Delta V_{SCF}.
!----------------------------------------------------------------------------
SUBROUTINE solve_linter(dvbarein, freq, drhoscf)
!-----------------------------------------------------------------------------

  USE bicgstab_module,      ONLY : bicgstab
  USE buffers,              ONLY : save_buffer, get_buffer
  USE check_stop,           ONLY : check_stop_now
  USE constants,            ONLY : degspin
  USE control_gw,           ONLY : niter_gw, nmix_gw, tr2_gw, &
                                   lgamma, convt, nbnd_occ, alpha_mix, &
                                   flmixdpot
  USE dv_of_drho_lr,        ONLY : dv_of_drho
  USE eqv,                  ONLY : dvpsi, evq
  USE fft_base,             ONLY : dfftp, dffts
  USE fft_interfaces,       ONLY : invfft, fwfft
  USE freq_gw,              ONLY : nfsmax
  USE gvecs,                ONLY : doublegrid
  USE gvect,                ONLY : nl
  USE io_global,            ONLY : stdout
  USE ions_base,            ONLY : nat
  USE kinds,                ONLY : DP
  USE klist,                ONLY : xk, wk, nkstot, ngk, igk_k
  USE lsda_mod,             ONLY : lsda, nspin, current_spin, isk
  USE mp,                   ONLY : mp_sum, mp_barrier
  USE mp_pools,             ONLY : inter_pool_comm
  USE noncollin_module,     ONLY : noncolin, npol, nspin_mag
  USE qpoint,               ONLY : npwq, nksq, igkq, ikks, ikqs
  USE timing_module,        ONLY : time_coul_solver
  USE units_gw,             ONLY : iubar, lrbar, &
                                   iuwfc, lrwfc, iudwfp 
  USE uspp,                 ONLY : okvan, vkb
  USE uspp_param,           ONLY : nhm
  USE wavefunctions_module, ONLY : evc
  USE wvfct,                ONLY : nbnd, npw, npwx, et, current_k

  IMPLICIT NONE

  !> the initial perturbuing potential
  COMPLEX(dp), INTENT(IN)  :: dvbarein (dffts%nnr)

  !> the frequencies for which the screened Coulomb is evaluated
  COMPLEX(dp), INTENT(IN)  :: freq(:)

  !> the change of the scf charge
  COMPLEX(dp), INTENT(OUT) :: drhoscf(dfftp%nnr, nspin_mag, 1)

  complex(DP), allocatable, target :: dvscfin(:,:,:)
  ! change of the scf potential 
  complex(DP), pointer :: dvscfins (:,:,:)
  ! change of the scf potential (smooth part only)
  complex(DP), allocatable :: drhoscfh(:,:,:), dvscfout(:,:,:)
  complex(DP), allocatable :: dbecsum (:,:,:), dbecsum_nc(:,:,:,:), aux1 (:,:)
  complex(DP), allocatable :: etc(:,:)
  complex(kind=DP) :: ZDOTC
  ! Misc variables for metals
  real(DP), external :: w0gauss, wgauss
  real(DP) , allocatable :: h_diag (:,:)
  real(DP) :: thresh, dr2
  ! thresh: convergence threshold
  ! dr2   : self-consistency error
  real(DP) :: weight
  !HL dbecsum (:,:,:,:), dbecsum_nc(:,:,:,:,:), aux1 (:,:)
  ! Misc work space
  ! ldos : local density of states af Ef
  ! ldoss: as above, without augmentation charges
  ! dbecsum: the derivative of becsum
  real(DP) :: tcpu, get_clock ! timing variables
  real(DP) :: meandvb

  integer :: kter,       & ! counter on iterations
             iter0,      & ! starting iteration
             ipert,      & ! counter on perturbations
             ibnd,       & ! counter on bands
             iter,       & ! counter on iterations
             lter,       & ! counter on iterations of linear system
             ltaver,     & ! average counter
             lintercall, & ! average number of calls to cgsolve_all
             ik, ikk,    & ! counter on k points
             ikq,        & ! counter on k+q points
             is,         & ! counter on spin polarizations
             nrec          ! the record number for dvpsi and dpsi
  integer :: irr, imode0, npe

  external ch_psi_all, cg_psi, h_psi_all, ch_psi_all_nopv
  real(kind=DP)    :: DZNRM2
  external ZDOTC, DZNRM2

  !> special treatment is possible for the first iteration
  LOGICAL first_iteration

  !> the number of frequencies
  INTEGER num_freq

  !> loop variable for frequencies
  INTEGER ifreq

  !! is the first frequency equal to 0
  LOGICAL zero_freq

  !> a copy of the input frequencies with negative values added
  !! this makes the call of the multishift solver easier
  COMPLEX(dp), ALLOCATABLE :: omega(:)

  !> size of this array
  INTEGER num_omega

  !> index in the array omega
  INTEGER iomega

  !> helper variable - length of array in BLAS routines
  INTEGER vec_size

  !> Change of the potential for e +- w
  !! first dimension  - number of G vector
  !! second dimension - number of bands
  !! third dimension  - number of frequencies 
  COMPLEX(dp), ALLOCATABLE :: dpsi(:,:,:)

  !> complex value of 0
  COMPLEX(dp), PARAMETER :: zero = CMPLX(0.0_dp, 0.0_dp, KIND = dp)

  !> complex value of 0.5
  COMPLEX(dp), PARAMETER :: half = CMPLX(0.5_dp, 0.0_dp, KIND = dp)

  !> 10^-10
  REAL(dp),    PARAMETER :: eps10 = 1e-10_dp

  CALL start_clock (time_coul_solver)

  ! determine number of frequencies
  ! note: currently on num_freq = 1 is implemented
  num_freq = SIZE(freq)
  IF (num_freq /= 1) CALL errore(__FILE__, "only num_freq = 1 implemented", num_freq)
  zero_freq = freq(1) == zero

  ! if the first frequency is 0, we don't need to add the negative value
  IF (zero_freq) THEN
    num_omega = 2 * num_freq - 1
  ELSE
    num_omega = 2 * num_freq
  END IF ! zero_freq

  ! create copy of the frequency array alternating adding negative
  ! values to the back
  ALLOCATE(omega(num_omega))
  omega(:num_freq) = freq
  IF (zero_freq) THEN
    omega(num_freq + 1:) = -freq(2:)
  ELSE
    omega(num_freq + 1:) = -freq
  END IF

  ! if the index of the last dimension is positive or negative, we evaluate
  ! (H + w S + alpha P) and (H - w S + alpha P), respectively
  ALLOCATE(dpsi(npwx * npol, nbnd, num_omega))
 
!HL- Allocate arrays for dV_scf (need to alter these from (dfftp%nnr, nspin_mag, npe) 
!to just (dfftp%nnr, nspin_mag).
  npe    = 1
  imode0 = 1
  irr    = 1
  ipert  = 1
  lter   = 0

  ALLOCATE(dvscfout(dfftp%nnr, nspin_mag, num_freq))
  ALLOCATE(drhoscfh(dfftp%nnr, nspin_mag, num_freq))
  ALLOCATE(etc(nbnd, nkstot))
  ALLOCATE(dbecsum((nhm * (nhm + 1)) / 2, nat, nspin_mag))

  ALLOCATE(dvscfin(dfftp%nnr, nspin_mag, num_freq))
  IF (doublegrid) THEN
    ALLOCATE(dvscfins(dffts%nnr, nspin_mag, num_freq))
  ELSE
    dvscfins => dvscfin
  ENDIF

!Complex eigenvalues
  IF (noncolin) ALLOCATE (dbecsum_nc(nhm, nhm, nat, nspin))
  ALLOCATE(aux1(dffts%nnr, npol))
  ALLOCATE(h_diag(npwx*npol, nbnd))

  iter0 =  0
  convt = .FALSE.

! The outside loop is over the iterations.
! niter_gw := maximum number of iterations
  
  DO kter = 1, niter_gw
    !
    first_iteration = (kter == 1)
    !
    iter       = kter + iter0
    ltaver     = 0
    lintercall = 0
    drhoscf    = zero
    drhoscfh   = zero
    dbecsum    = zero
    IF (noncolin) dbecsum_nc = zero 
    !
    DO ik = 1, nksq
      !
      ikk  = ikks(ik)
      ikq  = ikqs(ik)
      npw  = ngk(ikk)
      npwq = ngk(ikq)
      ! this is necessary for now until all instances of igkq
      ! are replaced with the appropriate igk_k
      igkq = igk_k(:,ikq)
      !
      current_k = ikq
      IF (lsda) current_spin = isk(ikk)
      !
      ! read unperturbed wavefunctions psi(k) and psi(k+q)
      !
      IF (nksq > 1) THEN
        IF (lgamma) THEN
          CALL get_buffer(evc, lrwfc, iuwfc, ikk)
        ELSE
          CALL get_buffer(evc, lrwfc, iuwfc, ikk)
          CALL get_buffer(evq, lrwfc, iuwfc, ikq)
        END IF
      END IF
      !
      ! compute beta functions and kinetic energy for k-point ikq
      ! needed by h_psi, called by ch_psi_all, called by cgsolve_all
      !
      CALL init_us_2(npwq, igk_k(1, ikq), xk(1, ikq), vkb)
      CALL g2_kin(ikq)
      !
      ! compute preconditioning matrix h_diag used by cgsolve_all
      !
      CALL h_prec(ik, evq, h_diag)
      !
      ! in the first iteration we initialize the linear system
      ! and may use the multishift solver
      IF (first_iteration) THEN
        !
        !  At the first iteration dvbare_q*psi_kpoint is calculated
        !  and written to file
        !
        nrec = ik
        CALL dvqpsi_us(dvbarein, ik, .FALSE.)
        CALL save_buffer(dvpsi, lrbar, iubar, nrec)
        !
        ! Orthogonalize dvpsi to valence states: ps = <evq|dvpsi>
        ! Apply -P_c^+.
        !-P_c^ = - (1-P_v^):
        CALL orthogonalize(dvpsi, evq, ikk, ikq, dpsi, npwq, .FALSE.)
        !
        ! At the first iteration initialize arrays to zero
        !
        dpsi     = zero
        dvscfin  = zero
        dvscfout = zero
        !
        ! starting threshold for iterative solution of the linear system
        !
        thresh = 1.0d-2
        !
        ! iterative solution of the linear system (H-eS)*dpsi=dvpsi,
        ! dvpsi=-P_c^+ (dvbare+dvscf)*psi , dvscf fixed.
        !
        ! use the BiCGstab solver
        !
        DO ibnd = 1, nbnd_occ(ik)
          CALL bicgstab(4, thresh, coulomb_operator, dvpsi(:npwq, ibnd), et(ibnd, ikk) + omega, dpsi(:npwq, ibnd, :))
        END DO ! ibnd
        !
      ELSE ! general case iter > 1
        !
        ! frequencies are the equivalent of perturbations in PHonon
        DO ifreq = 1, num_freq
          !
          ! After the first iteration dvbare_q*psi_kpoint is read from file
          !
          nrec = ik
          CALL get_buffer(dvpsi, lrbar, iubar, nrec)
          !
          ! calculates dvscf_q*psi_k in G_space, for all bands, k=kpoint
          ! dvscf_q from previous iteration (mix_potential)
          !
          DO ibnd = 1, nbnd_occ (ikk)
            CALL cft_wave(ik, evc (1, ibnd), aux1, +1)
            CALL apply_dpot(dffts%nnr, aux1, dvscfins(1, 1, ifreq), current_spin)
            CALL cft_wave(ik, dvpsi (1, ibnd), aux1, -1)
          ENDDO
          !
          !  In the case of US pseudopotentials there is an additional
          !  selfconsist term which comes from the dependence of D on
          !  V_{eff} on the bare change of the potential
          !
          CALL adddvscf(ifreq, ik)
          !
          ! Orthogonalize dvpsi to valence states: ps = <evq|dvpsi>
          ! Apply -P_c^+.
          !-P_c^ = - (1-P_v^):
          CALL orthogonalize(dvpsi, evq, ikk, ikq, dpsi, npwq, .FALSE.)
          !
          ! starting value for delta_psi is read from iudwf
          ! TODO: restarting is deactivated because bicgstab doesn't take
          !       a starting value in the current form
          !
          ! restart from default
          !
          dpsi = zero
          !
          ! threshold for iterative solution of the linear system
          !
          thresh = MIN(1.d-1 * SQRT(dr2), 1.d-2)
          !
          ! iterative solution of the linear system (H-eS)*dpsi=dvpsi,
          ! dvpsi=-P_c^+ (dvbare+dvscf)*psi , dvscf fixed.
          !
          ! determine index of -omega
          IF (zero_freq) THEN
            iomega = ifreq + num_freq - 1
          ELSE
            iomega = ifreq + num_freq
          END IF
          !
          ! use the BiCGstab solver
          !
          DO ibnd = 1, nbnd_occ(ik)
            !
            ! solve +omega
            CALL bicgstab(4, thresh, coulomb_operator, dvpsi(:npwq, ibnd), &
                          et(ibnd, ikk) + omega(ifreq:ifreq),              &
                          dpsi(:npwq, ibnd, ifreq:ifreq))
            !
            ! solve -omega
            IF (.NOT.zero_freq .OR. ifreq > 1) THEN
              CALL bicgstab(4, thresh, coulomb_operator, dvpsi(:npwq, ibnd), &
                            et(ibnd, ikk) + omega(iomega:iomega),            &
                            dpsi(:npwq, ibnd, iomega:iomega))
            END IF
            !
          END DO ! ibnd
          !
        END DO ! ifreq
        !
      END IF ! first_iteration
      !
      ! average between dpsi+ and dpsi-
      !
      IF (zero_freq) THEN
        !
        ! if the first frequency is 0, we only average +omega and -omega for all other frequencies
        !
        vec_size = npwx * npol * nbnd_occ(ikk) * (num_freq - 1)
        CALL ZSCAL(vec_size, half, dpsi(:,:,2), 1)
        CALL ZAXPY(vec_size, half, dpsi(:,:,num_freq + 1), 1, dpsi(:,:,2), 1)
        !
      ELSE ! not zero_freq
        !
        ! if the first frequency is not 0, we average +omega and -omega for all frequecies
        !
        vec_size = npwx * npol * nbnd_occ(ikk) * num_freq
        CALL ZSCAL(vec_size, half, dpsi(:,:,1), 1)
        CALL ZAXPY(vec_size, half, dpsi(:,:,num_freq + 1), 1, dpsi(:,:,1), 1)
        !
      END IF ! zero_freq
      !
      ltaver = ltaver + lter
      lintercall = lintercall + 1
      !
      nrec = ik
      !
      ! writes delta_psi+- on iunit iudwf, k=kpoint
      ! TODO: currently deactivated because solver doesn't take previous input
      !
      ! calculates dvscf, sum over k => dvscf_q_ipert
      !
      weight = wk (ikk)
      ! TODO change to account for ifreq
      IF (noncolin) THEN
        call incdrhoscf_nc(drhoscf(1, 1, 1), weight, ik, &
                           dbecsum_nc(1, 1, 1, 1), dpsi(1, 1, 1))
      ELSE
        call incdrhoscf(drhoscf(1, current_spin, 1), weight, ik, &
                        dbecsum(1, 1, current_spin), dpsi(1, 1, 1))
      ENDIF

    END DO ! on k-points
    !
    IF (doublegrid) THEN
      DO ifreq = 1, num_freq
        DO is = 1, nspin_mag
          CALL cinterpolate(drhoscfh(1, is, ifreq), drhoscf(1, is, ifreq), 1)
        END DO ! is
      END DO ! ifreq
    ELSE
      CALL ZCOPY(num_freq * nspin_mag * dfftp%nnr, drhoscf, 1, drhoscfh, 1)
    ENDIF
    !
    ! In the noncolinear, spin-orbit case rotate dbecsum
    !
    IF (noncolin .AND. okvan) CALL set_dbecsum_nc(dbecsum_nc, dbecsum, npe)
    !
    ! Now we compute for all perturbations the total charge and potential
    !
!    CALL addusddens(drhoscfh, dbecsum, imode0, npe, 0)
    !
    ! Reduce the delta rho across pools
    !
    CALL mp_sum(drhoscf, inter_pool_comm)
    CALL mp_sum(drhoscfh, inter_pool_comm)
    !
    ! After the loop over the perturbations we have the linear change
    ! in the charge density for each mode of this representation.
    ! Here we symmetrize them ...
    ! TODO check if/how symmetrization can be used
    !
    ! ... save them on disk and
    ! compute the corresponding change in scf potential
    !
    ! average value of dV_bare
    meandvb = SQRT(SUM(ABS(dvbarein)**2)) / REAL(dffts%nnr, KIND = dp)
    !
    DO ifreq = 1, num_freq
      !
      CALL ZCOPY(dfftp%nnr * nspin_mag, drhoscfh(1, 1, ifreq), 1, dvscfout(1, 1, ifreq), 1)
      !
      ! here we enforce zero average variation of the charge density
      ! if the bare perturbation does not have a constant term
      ! (otherwise the numerical error, coupled with a small denominator
      ! in the Coulomb term, gives rise to a spurious dvscf response)
      ! One wing of the dielectric matrix is particularly badly behaved
      !
      IF (meandvb < eps10) THEN 
        DO is = 1, nspin_mag
          CALL fwfft('Dense', dvscfout(:, is, ifreq), dfftp)
          dvscfout(nl(1), current_spin, ifreq) = zero
          CALL invfft('Dense', dvscfout(:, is, ifreq), dfftp)
        END DO ! is
      END IF
      !
      ! TODO write to file for restarting
      !
      !
      ! Compute the response HXC potential
      !
      CALL dv_of_drho (dvscfout(1, 1, ifreq), .FALSE.)
      !
      ! And we mix with the old potential
      !
      ! TODO replace this with ifreq
      !      probably need to mix all freq at once?
      IF (zero_freq) THEN
        !
        ! Density reponse in real space should be real at zero freq no matter what!
        ! just using standard broyden for the zero freq. case.
        !
        CALL mix_potential(2 * dfftp%nnr * nspin_mag, dvscfout(1, 1, ifreq), &
                           dvscfin(1, 1, ifreq), alpha_mix(kter), dr2, tr2_gw, &
                           iter, nmix_gw, flmixdpot, convt)
        !
      ELSE
        !
        ! use a mixing scheme working on complex
        !
        CALL mix_potential_c(dfftp%nnr * nspin_mag, dvscfout(1, 1, ifreq), &
                             dvscfin(1, 1, ifreq), alpha_mix(kter), dr2, tr2_gw, &
                             iter, nmix_gw, convt)
        !
      END IF ! frequency = Fermi energy
      !
    END DO ! ifreq
    !
    ! check that convergence hase been reached on ALL processors in this image
    CALL check_all_convt(convt)
    !
    IF (doublegrid) THEN
      DO is = 1, nspin_mag
        CALL cinterpolate(dvscfin(1,is,1), dvscfins(1,is,1), -1)
      END DO
    END IF
    !
    IF (convt) EXIT
    !
  END DO ! loop on kter (iterations)

  ! abort if solver doesn't converge
  IF (kter > niter_gw) THEN
    CALL errore(__FILE__, "Iterative solver did not converge within given number&
                         & of iterations", niter_gw)
  END IF

  tcpu = get_clock ('SGW')
  WRITE(stdout, '(/,5x," iter # ",i4," total cpu time :",f8.1)') iter, tcpu

  drhoscf = dvscfin
  
  DEALLOCATE(h_diag)
  DEALLOCATE(aux1)
  DEALLOCATE(dbecsum)
  DEALLOCATE(dvscfout)
  DEALLOCATE(drhoscfh)
  DEALLOCATE(dvscfin)
  DEALLOCATE(dpsi)
  IF (doublegrid) DEALLOCATE(dvscfins)
  IF (noncolin) DEALLOCATE(dbecsum_nc)

  CALL stop_clock(time_coul_solver)

END SUBROUTINE solve_linter

SUBROUTINE check_all_convt(convt)
  USE mp,        ONLY : mp_sum
  USE mp_images, ONLY : nproc_image, me_image, intra_image_comm
  IMPLICIT NONE
  LOGICAL,INTENT(in) :: convt
  INTEGER,ALLOCATABLE :: convt_check(:)
  !
  IF(nproc_image==1) RETURN
  !
  ALLOCATE(convt_check(nproc_image+1))
  !
  convt_check = 1
  IF(convt) convt_check(me_image+1) = 0
  !
  CALL mp_sum(convt_check, intra_image_comm)
  !CALL mp_sum(ios, inter_pool_comm)
  !CALL mp_sum(ios, intra_bgrp_comm)
  !
!  convt = ALL(convt_check==0)
  IF(ANY(convt_check==0).and..not.ALL(convt_check==0) ) THEN
    CALL errore('check_all_convt', 'Only some processors converged: '&
               &' something is wrong with solve_linter', 1)
  ENDIF
  !
  DEALLOCATE(convt_check)
  !
END SUBROUTINE

!! Wrapper for the linear operator call.
!!
!! Sets the necessary additional variables.
SUBROUTINE coulomb_operator(omega, psi, A_psi)

  USE control_gw,       ONLY: alpha_pv
  USE kinds,            ONLY: dp
  USE linear_op_module, ONLY: linear_op
  USE wvfct,            ONLY: npwx, current_k

  !> The initial shift.
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

  ! negative omega so that (H - omega) psi is calculated
  omega_ = -omega

  ! zero the elements outside of the definition
  psi_(:num_g, 1) = psi
  psi_(num_g + 1:, 1) = zero

  !
  ! apply the linear operator (H - omega + alpha Pv) psi
  !
  CALL linear_op(current_k, num_g, omega_, alpha_pv, psi_, A_psi_)

  ! extract result
  A_psi = A_psi_(:num_g,1)

  ! free memory
  DEALLOCATE(psi_, A_psi_)

END SUBROUTINE coulomb_operator

END MODULE solve_module
