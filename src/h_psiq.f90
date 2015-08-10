!
! Copyright (C) 2001-2007 Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!
!-----------------------------------------------------------------------
subroutine h_psiq (lda, n, m, psi, hpsi, spsi)
  !-----------------------------------------------------------------------
  !
  !     This routine computes the product of the Hamiltonian
  !     and of the S matrix with a m  wavefunctions  contained
  !     in psi. It first computes the bec matrix of these
  !     wavefunctions and then with the routines hus_1psi and
  !     s_psi computes for each band the required products
  !

  USE kinds,  ONLY : DP
  USE wavefunctions_module,  ONLY : psic, psic_nc
  USE becmod, ONLY : bec_type, becp, calbec
  USE noncollin_module, ONLY : noncolin, npol
  USE lsda_mod, ONLY : current_spin
  USE fft_base, ONLY : dffts
  USE fft_interfaces, ONLY: fwfft, invfft
  USE gvecs, ONLY: nls
  USE spin_orb, ONLY : domag
  USE scf,    ONLY : vrs
  USE uspp,   ONLY : vkb
  USE wvfct,  ONLY : g2kin
  USE qpoint, ONLY : igkq
  implicit none
  !
  !     Here the local variables
  !
  integer :: ibnd
  ! counter on bands

  integer :: lda, n, m
  ! input: the leading dimension of the array psi
  ! input: the real dimension of psi
  ! input: the number of psi to compute
  integer :: j
  ! do loop index

  complex(DP) :: psi (lda*npol, m), hpsi (lda*npol, m), spsi (lda*npol, m)
  complex(DP) :: sup, sdwn
  ! input: the functions where to apply H and S
  ! output: H times psi
  ! output: S times psi (Us PP's only)


  call start_clock ('h_psiq')

  call calbec ( n, vkb, psi, becp, m)
  !
  ! Here we apply the kinetic energy (k+G)^2 psi
  !
  hpsi=(0.d0,0.d0)
  do ibnd = 1, m
     do j = 1, n
        hpsi (j, ibnd) = g2kin (j) * psi (j, ibnd)
     enddo
  enddo
  IF (noncolin) THEN
     DO ibnd = 1, m
        DO j = 1, n
           hpsi (j+lda, ibnd) = g2kin (j) * psi (j+lda, ibnd)
        ENDDO
     ENDDO
  ENDIF
  !
  ! the local potential V_Loc psi. First the psi in real space
  !
  do ibnd = 1, m
     call start_clock ('firstfft')
     IF (noncolin) THEN
        psic_nc = (0.d0, 0.d0)
        do j = 1, n
           psic_nc(nls(igkq(j)),1) = psi (j, ibnd)
           psic_nc(nls(igkq(j)),2) = psi (j+lda, ibnd)
        enddo
        CALL invfft ('Wave', psic_nc(:,1), dffts)
        CALL invfft ('Wave', psic_nc(:,2), dffts)
     ELSE
        psic(:) = (0.d0, 0.d0)
        do j = 1, n
           psic (nls(igkq(j))) = psi (j, ibnd)
        enddo
        CALL invfft ('Wave', psic, dffts)
     END IF
     call stop_clock ('firstfft')
     !
     !   and then the product with the potential vrs = (vltot+vr) on the smooth grid
     !
     if (noncolin) then
        if (domag) then
           do j=1, dffts%nnr
              sup = psic_nc(j,1) * (vrs(j,1)+vrs(j,4)) + &
                    psic_nc(j,2) * (vrs(j,2)-(0.d0,1.d0)*vrs(j,3))
              sdwn = psic_nc(j,2) * (vrs(j,1)-vrs(j,4)) + &
                    psic_nc(j,1) * (vrs(j,2)+(0.d0,1.d0)*vrs(j,3))
              psic_nc(j,1)=sup
              psic_nc(j,2)=sdwn
           end do
        else
           do j=1, dffts%nnr
              psic_nc(j,1)=psic_nc(j,1) * vrs(j,1)
              psic_nc(j,2)=psic_nc(j,2) * vrs(j,1)
           enddo
        endif
     else
        do j = 1, dffts%nnr
           psic (j) = psic (j) * vrs (j, current_spin)
        enddo
     endif
     !
     !   back to reciprocal space
     !
     call start_clock ('secondfft')
     IF (noncolin) THEN
        CALL fwfft ('Wave', psic_nc(:,1), dffts)
        CALL fwfft ('Wave', psic_nc(:,2), dffts)
     !
     !   addition to the total product
     !
        do j = 1, n
           hpsi (j, ibnd) = hpsi (j, ibnd) + psic_nc (nls(igkq(j)), 1)
           hpsi (j+lda, ibnd) = hpsi (j+lda, ibnd) + psic_nc (nls(igkq(j)), 2)
        enddo
     ELSE
        CALL fwfft ('Wave', psic, dffts)
     !
     !   addition to the total product
     !
        do j = 1, n
           hpsi (j, ibnd) = hpsi (j, ibnd) + psic (nls(igkq(j)))
        enddo
     END IF
     call stop_clock ('secondfft')
  enddo
  !
  !  Here the product with the non local potential V_NL psi
  !

  call add_vuspsi (lda, n, m, hpsi)

  call s_psi (lda, n, m, psi, spsi)

  call stop_clock ('h_psiq')
  return
end subroutine h_psiq
