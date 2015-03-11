SUBROUTINE do_stern()
  USE io_global,  ONLY : stdout, ionode_id, meta_ionode
  USE kinds,      ONLY : DP
  USE disp,       ONLY : nqs, num_k_pts, xk_kpoints, w_of_q_start
  USE gwsigma,    ONLY : sigma_c_st
  USE gwsymm,     ONLY : ngmunique, ig_unique, use_symm, sym_friend, sym_ig
  USE control_gw, ONLY : done_bands, reduce_io, recover, tmp_dir_gw,&
                          ext_restart, bands_computed, bands_computed, nbnd_occ, lgamma,&
                          do_q0_only, solve_direct, tinvert, lrpa, do_epsil
  USE freq_gw,    ONLY : nfs
  USE units_gw,   ONLY : lrcoul, iuncoul
  USE klist,      ONLY : lgauss
  USE mp_global,  ONLY : inter_image_comm, intra_image_comm, &
                         my_image_id, nimage, root_image
  USE mp,              ONLY : mp_sum, mp_barrier
  USE mp_world,             ONLY : mpime

IMPLICIT NONE

  INTEGER :: iq, ik, ig, igstart, igstop, ios, iq1, iq2
  COMPLEX(DP), ALLOCATABLE :: scrcoul_g(:,:,:,:)
  LOGICAL :: do_band, do_iq, setup_pw, exst, do_matel

  ALLOCATE ( scrcoul_g( sigma_c_st%ngmt, sigma_c_st%ngmt, nfs, 1))
  ALLOCATE ( ig_unique( sigma_c_st%ngmt) )
  ALLOCATE ( sym_ig(sigma_c_st%ngmt))
  ALLOCATE ( sym_friend(sigma_c_st%ngmt))

  do_iq=.TRUE.
  setup_pw = .TRUE.
  do_band  = .TRUE.
  do_matel = .TRUE.

  IF(lgauss) WRITE(stdout, '(//5x,"SYSTEM IS METALLIC")')

  if(.not.do_epsil) then
      iq1 = w_of_q_start
      iq2 = nqs
  else
  ! In case we want to trace a line through the brillouin zone
  ! or get the screening for a particular grid q points (i.e. coulomb matel).
      iq1 = w_of_q_start
      iq2 = num_k_pts
  endif
    
   DO iq = iq1, iq2
    scrcoul_g(:,:,:,:) = (0.0d0, 0.0d0)
    CALL prepare_q(do_band, do_iq, setup_pw, iq)
    do_matel = .FALSE.
    CALL run_nscf(do_band, do_matel, iq)
    CALL initialize_gw()

    IF(use_symm) THEN
      WRITE(6,'("")')
      WRITE(6,'(5x, "SYMMETRIZING COULOMB Perturbations")')
      WRITE(6,'("")')
      CALL stern_symm()
    ELSE
      ngmunique = sigma_c_st%ngmt
      DO ig = 1, sigma_c_st%ngmt
         ig_unique(ig) = ig
      ENDDO
    ENDIF
!Need to distribute G vectors according to a sensible algorithm based
!on images which maintains, pool, and plane wave parallelism!
       if(nimage.gt.1) then
          CALL para_img(ngmunique, igstart, igstop)
       else
          igstart = 1
          igstop = ngmunique
       endif
       WRITE(6, '(5x, "iq ",i4, " igstart ", i4, " igstop ", i4)')iq, igstart, igstop
       CALL coulomb(iq, igstart, igstop, scrcoul_g)
!HLIM
       IF(nimage.gt.1) THEN
          CALL mp_sum(scrcoul_g, inter_image_comm)
       ENDIF

!Only the meta_image should write to file
       IF (meta_ionode) THEN
         CALL unfold_w(scrcoul_g,iq)
         IF(solve_direct.and.tinvert) WRITE(1000+mpime, '("UNFOLDING, INVERTING, WRITING W")')
         IF(solve_direct.and.tinvert) CALL invert_epsilon(scrcoul_g, iq)
         CALL davcio(scrcoul_g, lrcoul, iuncoul, iq, +1, ios)
       ENDIF
       call mp_barrier(inter_image_comm)
       CALL clean_pw_gw(iq)
       if(do_q0_only) GOTO 126
  ENDDO
126 CONTINUE
   WRITE(stdout, '("Finished Calculating Screened Coulomb")')
   DEALLOCATE( scrcoul_g )
   DEALLOCATE( ig_unique )
   DEALLOCATE( sym_ig )
   DEALLOCATE( sym_friend )
END SUBROUTINE do_stern
