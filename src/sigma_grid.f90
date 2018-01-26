!------------------------------------------------------------------------------
!
! This file is part of the SternheimerGW code.
! 
! Copyright (C) 2010 - 2017
! Henry Lambert, Martin Schlipf, and Feliciano Giustino
!
! SternheimerGW is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! SternheimerGW is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with SternheimerGW. If not, see
! http://www.gnu.org/licenses/gpl.html .
!
!------------------------------------------------------------------------------ 
!> This module provides the subroutines to initialize the Fourier transform
!! grids used for exchange and correlation.
!!
!! Because exchange and correlation are significantly less dispersive than the
!! charge density, we can reduce the energy cutoff used to calculate these
!! quantities. This module provides the routines to initialize the Fourier
!! transform types, generate the associated Fourier transform grid and print
!! some information about these grids.
!!
MODULE sigma_grid_module

  USE kinds,      ONLY: dp
  USE fft_types,  ONLY: fft_type_descriptor

  IMPLICIT NONE

  PUBLIC sigma_grid, sigma_grid_type

  !> contains the FFT grids used for exchange and correlation
  TYPE sigma_grid_type

    !> grid used for exchange
    TYPE(fft_type_descriptor) exch_fft

    !> the G vectors in the exchange grid
    REAL(dp), POINTER :: exch_gvec(:,:)

    !> grid used for correlation
    TYPE(fft_type_descriptor) corr_fft

    !> grid used for correlation (parallelized over images)
    TYPE(fft_type_descriptor) corr_par_fft

  END TYPE

CONTAINS

  !> Create a Fourier transform grid with a different energy cutoff.
  SUBROUTINE sigma_grid_create(comm, ecut, dfft, gvec)

    USE cell_base,      ONLY: tpiba2, at, bg
    USE control_flags,  ONLY: gamma_only
    USE fft_types,      ONLY: fft_type_init
    USE gvect,          ONLY: g, gg, mill
    USE mp_bands,       ONLY: nyfft
    USE recvec_subs,    ONLY: ggens
    USE stick_base,     ONLY: sticks_map

    !> communicator over which the routines are parallelized
    INTEGER,  INTENT(IN) :: comm

    !> The energy cutoff used for the custom type.
    REAL(dp), INTENT(IN) :: ecut

    !> The FFT type created
    TYPE(fft_type_descriptor), INTENT(OUT) :: dfft

    !> The G vectors in the generated grid
    REAL(dp), INTENT(OUT), POINTER, OPTIONAL :: gvec(:,:)

    !> cutoff of the G vectors
    REAL(dp) gcut

    !> number of g vectors on this process
    INTEGER num_g

    !> the sticks map created by fft type init
    TYPE(sticks_map) smap
 
#if defined(__MPI) && ! defined(__USE_3D_FFT)
    LOGICAL, PARAMETER :: lpara = .TRUE.
#else
    LOGICAL, PARAMETER :: lpara = .FALSE.
#endif

    !!
    !! 1. converts the energy cutoff to a cutoff for the G vectors
    !!
    gcut = ecut / tpiba2 

    !!
    !! 2. initialize the fft type
    !!
    CALL fft_type_init(dfft, smap, "rho", gamma_only, lpara, comm, at, bg, gcut, nyfft=nyfft)

    !!
    !! 3. generate the FFT grid
    !!
    CALL ggens(dfft, gamma_only, at, g, gg, mill, gcut, num_g, gvec)

  END SUBROUTINE sigma_grid_create

  !> Print info on local and global dimensions for real space grids
  SUBROUTINE sigma_grid_info(ecut, dfft, label)
  
    USE io_global,  ONLY: stdout
  
    IMPLICIT NONE
  
    !> The energy cutoff of the FFT grid
    REAL(dp), INTENT(IN) :: ecut 
  
    !> The FFT grid used
    TYPE(fft_type_descriptor), INTENT(IN) :: dfft

    !> The label of the type.
    CHARACTER(*), INTENT(IN)  :: label
  
    !> The description added to the label
    CHARACTER(*), PARAMETER   :: descr = 'Grid'
  
    !> The length of the label
    INTEGER len_label
  
    !> counter on the number of processes
    INTEGER iproc
  
    !
    ! add 1 for the space between label and description
    len_label = LEN_TRIM(label) + LEN_TRIM(descr) + 1
    !
    WRITE(stdout,*)
    WRITE(stdout,'(5x,a,1x,a)') TRIM(label), TRIM(descr)
    WRITE(stdout,'(5x,a)') REPEAT('-', len_label)
    WRITE(stdout,'(5x,a)') 'E_cutoff(Ry) num G vec'
    WRITE(stdout,'(5x,f8.2,7x,i6)') ecut, dfft%ngm
    WRITE(stdout,'(5x,a)') 'Global Dimensions   Local  Dimensions   Processor Grid'
    WRITE(stdout,'(5x,a)') '.X.   .Y.   .Z.     .X.   .Y.   .Z.     .X.   .Y.   .Z.'
    WRITE(stdout,'(2x,3(1x,i5),2x,3(1x,i5),2x,3(1x,i5))') &
      dfft%nr1, dfft%nr2, dfft%nr3, dfft%nr1, dfft%my_nr2p, dfft%my_nr3p, 1, dfft%nproc2, dfft%nproc3
    WRITE(stdout,'(5x,a,3(1x,i5))') 'Array leading dimensions ( nr1x, nr2x, nr3x )   = ', &
      dfft%nr1x, dfft%nr2x, dfft%nr3x
    WRITE(stdout,'(5x,a,1x,i9)') 'Local number of cell to store the grid ( nrxx ) = ', &
      dfft%nnr
    WRITE(stdout,'(5x,a)') 'size of the "Z" section of each processor'
    ! print local part for 10 processors at once
    DO iproc = 1, dfft%nproc3, 10
      WRITE(stdout,'(5x,a,10i5)') 'nr3p = ', dfft%nr3p(iproc : MIN(dfft%nproc3, iproc + 10))
    END DO ! iproc
    !
  END SUBROUTINE sigma_grid_info

  !> This subroutine generates the FFT grids for Exchange and Correlation.
  !!
  !! At the moment the necessary quantities are taken from the global modules.
  !! We call a grid generation routine for exchange and correlation. It prints
  !! some information about the generated grids and estimates the necessary
  !! memory.
  !!
  SUBROUTINE sigma_grid(freq, ecut_x, ecut_c, grid)
    !
    USE freqbins_module,  ONLY : freqbins_type
    USE io_global,        ONLY : stdout, ionode
    USE mp_bands,         ONLY : intra_bgrp_comm
    USE mp_images,        ONLY : inter_image_comm, nimage
    ! 
    IMPLICIT NONE
    !
    !> type that defines the frequencies used
    TYPE(freqbins_type),   INTENT(IN)  :: freq
    !
    !> the energy cutoff used for exchange
    REAL(dp),              INTENT(IN)  :: ecut_x
    !
    !> the energy cutoff used for correlation
    REAL(dp),              INTENT(IN)  :: ecut_c
    !
    !> the FFT grid used in the code
    TYPE(sigma_grid_type), INTENT(OUT) :: grid
    !
    !> number of bytes in a complex
    REAL(dp), PARAMETER :: complex_byte = 16.0_dp
    !> number of bytes in a mega byte
    REAL(dp), PARAMETER :: mega_byte = 10e6_dp
    !> convert a number of complex to a size in MB
    REAL(dp), PARAMETER :: in_MB = complex_byte / mega_byte
    !
    !> format to write the memory information
    CHARACTER(*), PARAMETER :: myfmt = '(5x,a,2x,f9.1,1x,a)'
    !
    !> helper variables for the number of G in exchange and correlation grid
    REAL(dp) num_g_x, num_g_c, num_g_ci
    !> helper variables for the number of r in exchange and correlation grid
    REAL(dp) num_r_x, num_r_c, num_r_ci
    !> helper product for the correlation grid
    REAL(dp) num_g_c_pr, num_r_c_pr

    !> number of frequencies used in the linear solver
    INTEGER num_freq

    !> number of frequencies used for the Green's function
    INTEGER num_green

    !> number of frequencies used for the self energy integration
    INTEGER num_sigma

    num_freq  = freq%num_freq()
    num_green = 2 * freq%num_coul()
    num_sigma = freq%num_sigma()

    !
    ! Generate the exchange grid
    !
    CALL sigma_grid_create(intra_bgrp_comm, ecut_x, grid%exch_fft, grid%exch_gvec)
    grid%exch_fft%rho_clock_label = 'fft_exch'
    IF (ionode) CALL sigma_grid_info(ecut_x, grid%exch_fft, 'Exchange')
  
    !
    ! Generate the correlation grid
    !
    CALL sigma_grid_create(intra_bgrp_comm, ecut_c, grid%corr_fft)
    grid%corr_fft%rho_clock_label = 'fft_corr'
    IF (ionode) CALL sigma_grid_info(ecut_c, grid%corr_fft, 'Correlation')
    !
    IF (nimage == 1) THEN
      ! reuse the same grid if only 1 image is used
      grid%corr_par_fft = grid%corr_fft
    ELSE
      ! create a grid parallelized over images
      CALL errore("image parallelization broken because ig_l2gt", 1)
      CALL sigma_grid_create(inter_image_comm, ecut_c, grid%corr_par_fft)
      grid%corr_par_fft%rho_clock_label = 'fft_corr_par'
      IF (ionode) CALL sigma_grid_info(ecut_c, grid%corr_par_fft, 'Correlation (images)')
    END IF

    !
    ! Print info about array size
    !
    num_g_x  = REAL(grid%exch_fft%ngm, KIND=dp)
    num_g_c  = REAL(grid%corr_fft%ngm, KIND=dp)
    num_g_ci = REAL(grid%corr_par_fft%ngm, KIND=dp)
    num_r_x  = REAL(grid%exch_fft%nnr, KIND=dp)
    num_r_c  = REAL(grid%corr_fft%nnr, KIND=dp)
    num_r_ci = REAL(grid%corr_par_fft%nnr, KIND=dp)
    !
    ! evaluate product of grid size
    num_g_c_pr = num_g_c * num_g_ci
    num_r_c_pr = num_r_c * num_r_ci
    !
    WRITE(stdout,*)
    WRITE(stdout,'(5x,a)') 'Memory Usage:'
    WRITE(stdout,*)
    WRITE(stdout, myfmt) "G(G, G'; w):    ", num_g_c_pr * REAL(num_green, KIND=dp) * in_MB, 'MB'
    WRITE(stdout, myfmt) "G(r, r'; w):    ", num_r_c_pr * REAL(num_green, KIND=dp) * in_MB, 'MB'
    WRITE(stdout, myfmt) "W(G, G'; w):    ", num_g_c**2 * REAL(num_freq,  KIND=dp) * in_MB, 'MB'
    WRITE(stdout, myfmt) "W(r, r'):       ", num_r_c_pr                            * in_MB, 'MB'
    WRITE(stdout, myfmt) "Sigma(G, G'; w):", num_g_c_pr * REAL(num_sigma, KIND=dp) * in_MB, 'MB'
    WRITE(stdout, myfmt) "Sigma(r, r'; w):", num_r_c_pr * REAL(num_sigma, KIND=dp) * in_MB, 'MB'
    WRITE(stdout, myfmt) "V(G, G'):       ", num_g_x**2                            * in_MB, 'MB'
    WRITE(stdout, myfmt) "V(r, r'):       ", num_r_x**2                            * in_MB, 'MB'
    WRITE(stdout,*)

  END SUBROUTINE sigma_grid

END MODULE sigma_grid_module
