SUBROUTINE sigma_c(ik0) 
! G TIMES W PRODUCT
  USE io_global,     ONLY : stdout, ionode_id, ionode
  USE kinds,         ONLY : DP
  USE lsda_mod,      ONLY : nspin
  USE constants,     ONLY : e2, fpi, RYTOEV, tpi, eps8, pi
  USE disp,          ONLY : nqs, nq1, nq2, nq3, wq, x_q, xk_kpoints
  USE control_gw,    ONLY : lgamma, eta, godbyneeds, padecont, cohsex, modielec, trunc_2d
  USE klist,         ONLY : wk, xk
  USE io_files,      ONLY : iunigk, prefix, tmp_dir
  USE wvfct,         ONLY : nbnd, npw, npwx, igk, g2kin, et
  USE eqv,           ONLY : evq, eprec
  USE freq_gw,       ONLY : fpol, fiu, nfs, nfsmax, &
                            nwcoul, nwgreen, nwalloc, nwsigma, wtmp, wcoul, &
                            wgreen, wsigma, wsigmamin, wsigmamax, &
                            deltaw, wcoulmax, ind_w0mw, ind_w0pw
  USE units_gw,      ONLY : iuncoul, iungreen, iunsigma, lrsigma, lrcoul, lrgrn, iuwfc, lrwfc
  USE qpoint,        ONLY : xq, npwq, igkq, nksq, ikks, ikqs
  USE gwsigma,       ONLY : ngmsco, sigma, sigma_g, nrsco, nlsco, fft6_g2r, ecutsco, ngmsig,&
                            nr1sco, nr2sco, nr3sco, ngmgrn, ngmpol
  USE gvect,         ONLY : g, ngm, ecutwfc, nl
  USE cell_base,     ONLY : tpiba2, tpiba, omega, alat, at
  USE symm_base,     ONLY : nsym, s, time_reversal, t_rev, ftau, invs, nrot
  USE mp_global,     ONLY : inter_pool_comm, intra_pool_comm, mp_global_end, mpime, npool, &
                            nproc_pool, me_pool, my_pool_id, nproc
  USE mp,            ONLY : mp_barrier, mp_bcast, mp_sum
  USE fft_scalar,    ONLY : cfft3d
  USE modes,         ONLY : nsymq, invsymq, gi, gimq, irgq, irotmq, minus_q
  USE wavefunctions_module, ONLY : evc
  USE control_flags,        ONLY : noinv

  IMPLICIT NONE
  COMPLEX(DP)         :: ci, czero
  COMPLEX(DP)         :: phase
  COMPLEX(DP)         :: aux (nrsco)
!For running PWSCF need some variables 
  LOGICAL             :: pade_catch
  LOGICAL             :: found_q
  LOGICAL             :: limit, limq, inv_q, found
!Pade arrays
  COMPLEX(DP), ALLOCATABLE :: z(:), u(:), a(:)
!W arrays 
  COMPLEX(DP), ALLOCATABLE :: scrcoul_g (:,:,:)
  COMPLEX(DP), ALLOCATABLE :: scrcoul_g_R (:,:,:)
  COMPLEX(DP), ALLOCATABLE :: scrcoul_pade_g (:,:)
  COMPLEX(DP), ALLOCATABLE :: scrcoul(:,:)
!v array
!COMPLEX(DP), ALLOCATABLE ::  barcoul(:,:), barcoulr(:,:), barcoul_R(:,:)
  REAL(DP) :: qg2, qg, qxy, qz
!G arrays:
  COMPLEX(DP), ALLOCATABLE :: greenf_g(:,:), greenfr(:,:)
!Integration Variable 
  COMPLEX(DP) :: cprefac
!FREQUENCY GRIDS/COUNTERS
  INTEGER  :: iwim, iw, ikq
  INTEGER  :: iw0, iw0mw, iw0pw
  REAL(DP) :: w_ryd(nwcoul)
!COUNTERS
  INTEGER :: ig, igp, irr, icounter, ir, irp
  INTEGER :: iqstart, iqstop, iqs, nkr
  INTEGER :: iq, ipol, iqrec
  INTEGER :: ikmq, ik0, ik, nkpool
  INTEGER :: rec0, ios
  INTEGER :: counter, ierr
  INTEGER :: inversym, screening
!SYMMETRY
  REAL(DP)              :: xq_ibk(3), xq_ibz(3)
  INTEGER               :: isym, jsym
  INTEGER, ALLOCATABLE  :: gmapsym(:,:)
!For G^NA
  INTEGER     :: igkq_ig(npwx) 
  INTEGER     :: igkq_tmp(npwx) 
  INTEGER     :: ss(3,3)
  COMPLEX(DP), ALLOCATABLE  ::  eigv(:,:)
!q-vector of coulomb potential xq_coul := k_{0} - xk(ik)
  REAL(DP) :: xq_coul(3)
  REAL(DP) :: rcut, spal, zcut
  INTEGER  :: ibnd
!CHECK FOR NAN's
  REAL(DP)     :: ar, ai
!For dirac delta fxn.
  REAL(DP)     :: dirac, x, support

!File related:
  character(len=256) :: tempfile, filename
!Complete file name
  integer*8 :: unf_recl

#define DIRECT_IO_FACTOR 8 
! #ifdef __PARA
!       scrcoul_g = czero
!       if (me.eq.1.and.mypool.eq.1) then
! #endif
! #ifdef __PARA
!       endif
!       use poolreduce to broadcast the results to every pool
!       call poolreduce ( 2 * ngms * ngms * nwim, scrcoul_g)
! #endif
! iG(W-v)
   ALLOCATE ( scrcoul_g      (ngmpol, ngmpol, nfs)     )
   ALLOCATE ( scrcoul_g_R    (ngmpol, ngmpol, nfs)     )
   ALLOCATE ( scrcoul_pade_g (ngmpol, ngmpol)          )
   ALLOCATE ( greenf_g       (ngmgrn, ngmgrn)          )
!These go on the big grid...
   ALLOCATE ( scrcoul        (nrsco, nrsco)            )
   ALLOCATE ( greenfr        (nrsco, nrsco)            )
!barcoul
!  ALLOCATE ( barcoul     (ngmpol, ngmpol)  )
!  ALLOCATE ( barcoulr    (nrsco,  nrsco)   )
!  ALLOCATE ( barcoul_R   (ngmpol,  ngmpol) )
!Technically only need gmapsym up to ngmpol or ngmgrn...
   ALLOCATE ( gmapsym  (ngm, nrot)   )
   ALLOCATE ( eigv     (ngm, nrot)   )
!This is a memory hog...
   ALLOCATE ( sigma          (nrsco, nrsco, nwsigma)   )
   ALLOCATE  (z(nfs), a(nfs), u(nfs))
!do we need two instances of the frequency?
   w_ryd(:) = wcoul(:)/RYTOEV
   WRITE(6," ")
   WRITE(6,'(4x,"Direct product GW for k0(",i3," ) = (",3f12.7," )")') ik0, (xk(ipol, ik0), ipol=1,3)
   WRITE(6," ")
   WRITE(6,'(4x, "ngmsco, ", i4, " nwsigma, ", i4)') ngmsco, nwsigma
   WRITE(6,'(4x, "nrsco, ", i4, " nfs, ", i4)') nrsco, nfs
   ci = (0.0d0, 1.d0)
   czero = (0.0d0, 0.0d0)
   sigma(:,:,:) = (0.0d0, 0.0d0)
   limit=.false.
   CALL start_clock('sigmac')
   CALL gmap_sym(nrot, s, ftau, gmapsym, eigv, invs)
   if(allocated(sigma)) then
     WRITE(6,'(4x,"Sigma allocated")')
   else
     WRITE(6,'(4x,"Sigma too large!")')
     CALL mp_global_end()
     STOP
   endif

   WRITE(6,'("nsym, nsymq, nsymbrav ", 3i4)'), nsym, nsymq, nrot 

!Set appropriate weights for points in the brillouin zone.
!Weights of all the k-points are in odd positions in list.
!nksq is number of k points not including k+q.
   wq(:) = 0.0d0
   do iq = 1, nksq
      if(lgamma) then
         write(6, '(" lgamma ")')
         wq(iq) = 0.5d0*wk(iq) 
      else
         wq(iq) = 0.5d0*wk(2*iq-1) 
      endif
   enddo
!Every processor needs access to the files: _gw0si.coul1 and _gw0si.green1
call mp_barrier(inter_pool_comm)
#ifdef __PARA
if(.not.ionode) then
!OPEN coulomb file (only written to by head node).
   filename = trim(prefix)//"."//"coul1"
   tempfile = trim(tmp_dir) // trim(filename)
   unf_recl = DIRECT_IO_FACTOR * int(lrcoul, kind=kind(unf_recl))
   open(iuncoul, file = trim(adjustl(tempfile)), iostat = ios, &
   form = 'unformatted', status = 'OLD', access = 'direct', recl = unf_recl)
!OPEN green file (only written to by head node as well).
   filename = trim(prefix)//"."//"green1"
   tempfile = trim(tmp_dir) // trim(filename)
   unf_recl = DIRECT_IO_FACTOR * int(lrgrn, kind=kind(unf_recl))
   open(iungreen, file = trim(adjustl(tempfile)), iostat = ios, &
   form = 'unformatted', status = 'OLD', access = 'direct', recl = unf_recl)
endif
#endif

#ifdef __PARA
      npool = nproc / nproc_pool
      write(stdout,'("npool", i4, i5)') npool, nksq
      if (npool.gt.1) then
      ! number of q-vec per pool and remainder
        nkpool = nksq / npool
        nkr = nksq - nkpool * npool
      ! the remainder goes to the first nkr pools
        if ( my_pool_id < nkr ) nkpool = nkpool + 1
        iqs = nkpool * my_pool_id + 1
        if ( my_pool_id >= nkr ) iqs = iqs + nkr
      ! the index of the first and the last g vec in this pool
        iqstart = iqs
        iqstop  = iqs - 1 + nkpool
        write (stdout,'(/4x,"Max n. of Kpoint in Sigma_C per pool = ",i5)') iqstop-iqstart+1
      else
#endif
       iqstart = 1
       iqstop = nksq
#ifdef __PARA
      endif
#endif
!ONLY PROCESSORS WITH K points to process: 
IF(iqstop-iqstart+1.ne.0) THEN
   WRITE(1000+mpime, '("mpime ", i4, "  iqstart, iqstop: ", 2i5)')mpime, iqstart, iqstop
   if (nksq.gt.1) rewind (unit = iunigk)
DO iq = iqstart, iqstop
      if (lgamma) then
          ikq = iq
      else
!k+q is in even positions of list (k,k+q)
          ikq = 2*iq
      endif
!q point for convolution \sum_{q \in IBZ_{k}} G_{k+q} W_{-q}
!  q = (k0 + q) - k0
!  xq_ibk(:) = xk(:,ikq) - xk_kpoints(:, ik0)
!  by actually searching for -q and calculating w of -q  
!  we ensure there is no confusion in which symmetry routine is required.
!  SYMMFIX
!  -q =  k0 - (k0 + q)
     xq_ibk(:) = xk_kpoints(:, ik0) - xk(:, ikq)
!Find which symmetry operation rotates xq_ibk back to
!The irreducible brillouin zone and which q \in IBZ it corresponds to.
!q is stored in the list x_q as positive q but all the calculations have
!been done at -q therefore we are just going to calculate \Sum G_{k+q}W_{-q}
   inv_q=.false.
   call find_q_ibz(xq_ibk, s, iqrec, isym, found_q, inv_q)
   if(lgamma) npwq=npw 
   write(6, *)  
!  write(6, '("xk point")')
!  write(6, '(3f11.7)') xk_kpoints(:,ik0)
   write(6, '("xq_IBK point")')
   write(6, '(3f11.7)') xq_ibk
   write(6, '("equivalent xq_IBZ point, symop, iqrec")')
   write(6, '(3f11.7, 2i4)') x_q(:,iqrec), isym, iqrec
   write(6,*)

   write(1000+mpime, *)  
   write(1000+mpime, '("xq_IBK point")')
   write(1000+mpime, '(3f11.7)') xq_ibk
   write(1000+mpime, '("equivalent xq_IBZ point, symop, iqrec")')
   write(1000+mpime, '(3f11.7, 2i4)') x_q(:, iqrec), isym, iqrec

!Need a loop to find all plane waves below ecutsco when 
!igkq takes us outside of this sphere.
!igkq_tmp is gamma centered index up to ngmsco,
!igkq_ig  is the linear index for looping up to npwq.
!Also since we are in parallel here I might have to use the gk_sort
!igk is fine!!!
!EXCHANGE TEST
!    call davcio (evq, lrwfc, iuwfc, ikq, - 1)
!     CALL gk_sort( xk(1,ikq), ngm, g, ecutwfc / tpiba2, npw, igkq, g2kin )
!     counter = 0
!     igkq_tmp(:) = 0
!     igkq_ig(:)  = 0 
!     do ig = 1, npwx
!        if((igkq(ig).le.ngmgrn).and.((igkq(ig)).gt.0)) then
!            counter = counter + 1
!           !index in total G grid.
!            igkq_tmp (counter) = igkq(ig)
!           !index for loops 
!            igkq_ig  (counter) = ig
!        endif
!     enddo
!Dielectric Function should be written to file at this point
!So we read that in, rotate it, and then apply the coulomb operator.

     scrcoul_g(:,:,:)   = dcmplx(0.0d0, 0.0d0)
     scrcoul_g_R(:,:,:) = dcmplx(0.0d0, 0.0d0)
     if(.not.modielec) CALL davcio(scrcoul_g, lrcoul, iuncoul, iqrec, -1)

!Rotate G_vectors for FFT.
!In EPW FG checked that gmapsym(gmapsym(ig,isym),invs(isym)) = ig
!I have checked that here as well and it works.
!write(6,'(11i4)')gmapsym(gmapsym(:ngmsco,isym),invs(isym))
!Take a look at rotated G-vect map:
!for systems with ftau != 0 should also multiply each matrix element
!by phase, e^{iG'\tau}.
!Another one of these nested loops. 
!Two strategies or alternatives:
!1) Could pad scrcoul_g_R so that all the vectors still fall in 
!   side of it up to ngmsco then trim them off later.
!2) Modify gmapsym so that it only keeps vectors up to ngmsco.

     do igp = 1, ngmpol
        do ig = 1, ngmpol
           if((gmapsym(ig,isym).le.ngmpol).and.(gmapsym(igp,isym).le.ngmpol) &
               .and.(gmapsym(ig,isym).gt.0).and.(gmapsym(ig,isym).gt.0)) then
               do iwim = 1, nfs
!Rotating dielectric matrix with phase factor 
!for nonsymmorphic space groups normal:
               phase = eigv(ig,isym)*conjg(eigv(igp,isym))
               scrcoul_g_R(ig, igp, iwim) = scrcoul_g(gmapsym(ig,isym), gmapsym(igp,isym),iwim)*phase
               enddo
           endif
        enddo
     enddo
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!Generate bare coulomb:                      !!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!HL using  sax cutoff
!this should be L_{z}/2
!rcut = 0.50d0*minval(sqrt(sum(at**2,1)))*alat*tpi
!rcut = rcut-rcut/50.0d0
rcut = (float(3)/float(4)/pi*omega*float(nq1*nq2*nq3))**(float(1)/float(3))
!Sax for silicon
!    rcut = 21.329d0
if(.not.modielec) then
DO iw = 1, nfs
   DO ig = 1, ngmpol
!SPHERICAL SCREENING
       qg2 = (g(1,ig) + xq_ibk(1))**2 + (g(2,ig) + xq_ibk(2))**2 + (g(3,ig)+xq_ibk(3))**2
       limq = (qg2.lt.eps8) 
       IF(.not.limq) then
           do igp = 1, ngmpol
              scrcoul_g_R(ig, igp, iw) = scrcoul_g_R(ig,igp,iw)*dcmplx(e2*fpi/(tpiba2*qg2), 0.0d0)
           enddo
       ENDIF
       qg = sqrt(qg2)
       spal = 1.0d0 - cos(rcut*sqrt(tpiba2)*qg)
       !spal = 1.0d0 - cos(rcut*qg)
!Normal case using truncated coulomb potential.
       if(.not.limq) then
          do igp = 1, ngmpol
              scrcoul_g_R(ig, igp, iw) = scrcoul_g_R(ig,igp,iw)*dcmplx(spal, 0.0d0)
          enddo
       else
!should only occur case iq->0, ig = 0 use vcut (q(0) = (4pi*e2*Rcut^{2})/2
!             write(6,'("Taking Limit.")')
!             write(6,*) (rcut)
!             write(6,*) (fpi*e2*(rcut**2))/2.0d0
!             write(6,*) ig, iw
!             write(6,*) g(:, ig)
!             write(6,*) xq_ibk(:)
!             write(6,*) qg2
!for omega=0,q-->0, G=0 the real part of the head of the dielectric matrix should be real
!we enforce that here:
             if(iw.eq.1) then
                scrcoul_g_R(ig, igp, iw) = real(scrcoul_g_R(ig,igp,iw))
             endif
             do igp = 1, ngmpol
                scrcoul_g_R(ig, igp, iw) = scrcoul_g_R(ig,igp,iw)*dcmplx((fpi*e2*(rcut**2))/2.0d0, 0.0d0)
             enddo
       endif
   ENDDO!ig
ENDDO!nfs
endif

!zeroing wings of W again!
    if(iq.eq.1) then
      do iw = 1, nfs
       do ig = 2, ngmpol
          scrcoul_g_R(ig,1,iw)  = dcmplx(0.0d0, 0.d0)
       enddo
       do igp = 2, ngmpol
          scrcoul_g_R(1,igp,iw) = dcmplx(0.0d0, 0.d0)
       enddo
      enddo
    endif

    if(.not.modielec) then 
        if(godbyneeds) then
        do ig = 1, ngmpol
          do igp = 1, ngmpol 
!         for godby-needs plasmon pole the algebra is done assuming real frequency*i...
!         that is: the calculation is done at i*wp but we pass a real number as the freq. 
               do iw = 1, nfs
                 z(iw) = dcmplx(aimag(fiu(iw)), 0.0d0)
                 u(iw) = scrcoul_g_R(ig, igp, iw)
               enddo
               CALL godby_needs_coeffs(nfs, z, u, a)
               do iw = 1, nfs 
!just overwrite scrcoul_g_R with godby-needs coefficients.
                  scrcoul_g_R (ig, igp, iw) = a(iw)
               enddo
          enddo
        enddo
        else if (padecont) then
          do igp = 1, ngmpol
           do ig = 1, ngmpol
!     Pade input points on the imaginary axis
              do iw = 1, nfs
                 z(iw) = fiu(iw)
                 u(iw) = scrcoul_g_R (ig, igp, iw)
              enddo
              call pade_coeff ( nfs, z, u, a)
!     Overwrite scrcoul with Pade coefficients to be passed to pade_eval.
             do iw = 1, nfs 
                scrcoul_g_R (ig, igp, iw) = a(iw)
             enddo
           enddo !enddo on ig
        enddo  !enddo on igp
        else if(.not.padecont.and..not.godbyneeds) then
                 WRITE(6,'("No screening model chosen!")')
        endif
    endif
!Start integration over iw +/- wcoul. 
    WRITE(6,'("Starting Frequency Integration")')
    DO iw = 1, nwcoul
       scrcoul_pade_g(:,:) = (0.0d0, 0.0d0)
    if(.not.modielec) then
        do ig = 1, ngmpol
           do igp = 1, ngmpol
              do iwim = 1, nfs
                  z(iwim) = fiu(iwim)
                  a(iwim) = scrcoul_g_R (ig,igp,iwim)
              enddo
              pade_catch=.false.
              if(padecont) then
                 call pade_eval ( nfs, z, a, dcmplx(w_ryd(iw), eta), scrcoul_pade_g (ig,igp))
              else if(godbyneeds) then
                scrcoul_pade_g(ig,igp) = a(2)/(dcmplx(w_ryd(iw)**2,0.0d0)-(a(1)-(0.0d0,1.0d0)*eta)**2)
              else 
                   WRITE(6,'("No screening model chosen!")')
                   STOP
                   call mp_global_end()
              endif
           enddo
        enddo
    else if(modielec)  then
          do ig = 1, ngmpol
             call mod_diel(ig, xq_ibk, w_ryd(iw), scrcoul_pade_g(ig,ig), 1)
            !rewrite as fxns:
            !scrcoul_pade_g(ig,ig) = mod_dielec_(xq,w_ryd,ig)*v_(q+G,truncation)
             qg2 = (g(1,ig) + xq_ibk(1))**2 + (g(2,ig) + xq_ibk(2))**2 + (g(3,ig)+xq_ibk(3))**2
             limq = (qg2.lt.eps8) 
             IF(.not.limq) then
                scrcoul_pade_g(ig, ig) = scrcoul_pade_g(ig,ig)*dcmplx(e2*fpi/(tpiba2*qg2), 0.0d0)
             ENDIF
             qg = sqrt(qg2)
             spal = 1.0d0 - cos(rcut*sqrt(tpiba2)*qg)
!Normal case using truncated coulomb potential.
             if(.not.limq) then
                   scrcoul_pade_g(ig, ig) = scrcoul_pade_g(ig,ig)*dcmplx(spal, 0.0d0)
             else
                   scrcoul_pade_g(ig, ig) = scrcoul_pade_g(ig,ig)*dcmplx((fpi*e2*(rcut**2))/2.0d0, 0.0d0)
             endif
          enddo
    endif
!W(G,G';w)
        czero = (0.0d0, 0.0d0)
        scrcoul(:,:) = czero
        do ig = 1, ngmpol
           aux(:) = czero
           do igp = 1, ngmpol
                    aux(nlsco(igp)) = scrcoul_pade_g(ig,igp)
           enddo
           call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, +1)
           do irp = 1, nrsco
              scrcoul(ig, irp) = aux(irp) / omega 
           enddo
        enddo

        do irp = 1, nrsco
           aux = czero
           do ig = 1, ngmpol
               aux(nlsco(ig)) = conjg(scrcoul(ig,irp))
           enddo
           call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, +1)
!@         scrcoul(1:nrsco,irp) = conjg ( aux )
!@conjg sigma so matrix elements are correct.
           scrcoul(1:nrsco,irp) = aux 
        enddo
!Now have W(r,r';omega')
       ! simpson quadrature: int_w1^wN f(w)dw = deltaw * 
       ! [ 1/3 ( f1 + fN ) + 4/3 sum_even f_even + 2/3 sum_odd f_odd ]
!        cprefac = (deltaw/RYTOEV) * wq(iq) * (0.0d0, 1.0d0)/ tpi
!@
         cprefac = (deltaw/RYTOEV) * wq(iq) * (0.0d0, -1.0d0)/ tpi

         if ( iw/2*2.eq.iw ) then
            cprefac = cprefac * 4.d0/3.d0
         else
            cprefac = cprefac * 2.d0/3.d0
         endif
       ! Presumably the fxn should be zero at the cutoff but might as well be consistent...
         if (iw.eq.1) then
             cprefac = (1.0d0/3.0d0)*(deltaw/RYTOEV) * wq(iq) * (0.0d0, 1.0d0)/ tpi
         else if (iw.eq.nwcoul) then
             cprefac = (1.0d0/3.0d0)*(deltaw/RYTOEV) * wq(iq) * (0.0d0, 1.0d0)/ tpi
         endif

         do iw0 = 1, nwsigma
            iw0mw = ind_w0mw (iw0,iw)
            iw0pw = ind_w0pw (iw0,iw)
!rec0 = (iw0mw-1) * 1 * nqs + (ik0-1) * nqs + (iq-1) + 1
            rec0 = (iw0mw-1) * 1 * nksq + (iq-1) + 1
            CALL davcio( greenf_g, lrgrn, iungreen, rec0, -1 )
!(Rotate green)
            greenfr(:,:) = czero
            do ig = 1, ngmgrn
               aux(:) = czero
               do igp = 1, ngmgrn
                  aux(nlsco(igp)) = greenf_g(ig,igp)
               enddo
               call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, +1)
               do irp = 1, nrsco
                 greenfr(ig, irp) = aux(irp)/omega
               enddo
            enddo
!additionally this means what I've actually calculated in green linsys is G = \psi_k^*(G)\psi_k(G')
!instead of \psi_{k}(G)\psi_{k}^*(G'), in Si inversion symmetry means:  
!G = \psi_{-k}(-G)\psi^*_-k(-G') 
!WHAT IF WE DON'T HAVE INVERSION SYMMETRY?
            do irp = 1, nrsco
               aux = czero
                    do ig = 1, ngmgrn
                          aux(nlsco(ig)) = conjg(greenfr(ig,irp))
                    enddo
                    call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, +1)
                    greenfr(1:nrsco,irp) = conjg ( aux )
            enddo
            sigma (:,:,iw0) = sigma (:,:,iw0) + cprefac * greenfr(:,:)*scrcoul(:,:)
!Now have G(r,r';omega-omega')
!rec0 = (iw0pw-1) * 1 * nqs + (ik0-1) * nqs + (iq-1) + 1
            rec0 = (iw0pw-1) * 1 * nksq + (iq-1) + 1
            CALL davcio(greenf_g, lrgrn, iungreen, rec0, -1)
!Rotate green...
!Inlining FFT:
            greenfr(:,:) = czero
            do ig = 1, ngmgrn
               aux(:) = czero
               do igp = 1, ngmgrn
                  aux(nlsco(igp)) = greenf_g(ig,igp)
               enddo
               call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, +1)
               do irp = 1, nrsco
                  greenfr(ig, irp) = aux(irp) / omega
               enddo
            enddo
            do irp = 1, nrsco
               aux = czero
                    do ig = 1, ngmgrn
                           aux(nlsco(ig)) = conjg(greenfr(ig,irp))
                    enddo
               call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, +1)
               greenfr(1:nrsco,irp) = conjg ( aux )
            enddo
            sigma (:,:,iw0) = sigma (:,:,iw0) + cprefac * greenfr(:,:)*scrcoul(:,:)
        ENDDO !on iw0  
      ENDDO ! on frequency convolution over w'
    ENDDO ! end loop iqstart, iqstop 
ENDIF

    DEALLOCATE ( gmapsym          )
    DEALLOCATE ( greenfr          )
    DEALLOCATE ( greenf_g         )
    DEALLOCATE ( scrcoul          )
    DEALLOCATE ( scrcoul_pade_g   )
    DEALLOCATE ( scrcoul_g, scrcoul_g_R )
    DEALLOCATE ( z,a,u )

#ifdef __PARA
    CALL mp_barrier(inter_pool_comm)
    CALL mp_sum(sigma, inter_pool_comm)
    CALL mp_barrier(inter_pool_comm)
#endif __PARA


IF (ionode) then
  ALLOCATE ( sigma_g (ngmsco, ngmsco, nwsigma))
  if(allocated(sigma_g)) then
     WRITE(6,'(4x,"Sigma_g allocated")')
  else
     WRITE(6,'(4x,"Sigma_g too large!")')
     CALL mp_global_end()
     STOP
  endif

    WRITE(6,'(4x,"Sigma in G-Space")')
    sigma_g = (0.0d0,0.0d0)
    do iw = 1, nwsigma
      do ir = 1, nrsco
        aux = (0.0d0, 0.0d0)
        do irp = 1, nrsco
           aux(irp) = sigma(ir,irp,iw)
        enddo
        call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, -1)
        do igp = 1, ngmsco
           sigma (ir, igp, iw) = aux(nlsco(igp))
        enddo
      enddo
      do igp = 1, ngmsco
        aux = czero
        do ir = 1, nrsco
          aux(ir) = conjg ( sigma(ir,igp,iw) )
        enddo
        call cfft3d (aux, nr1sco, nr2sco, nr3sco, nr1sco, nr2sco, nr3sco, -1)
        do ig = 1, ngmsco
           sigma (ig,igp,iw) = conjg ( aux( nlsco( ig )) ) * omega
        enddo
      enddo
    enddo

    do iw = 1, nwsigma
      do igp = ngmsco + 1, nrsco
         do ig = ngmsco + 1, nrsco
               sigma (ig, igp, iw) = (0.0d0, 0.0d0)
         enddo 
      enddo
    enddo
!sigma_g = sigma(1:ngmsco,1:ngmsco,:)
    do iw = 1, nwsigma
      do igp = 1, ngmsco
       do ig = 1, ngmsco
           sigma_g(ig,igp,iw)  = sigma(ig,igp,iw)
       enddo
      enddo
    enddo 

!Now write Sigma in G space to file. 
!HL Original:
!Just storing in first record no matter what k-point.
!HLFULLSIG
    CALL davcio (sigma_g, lrsigma, iunsigma, ik0, 1)
!or could store sigma same way green's fxn is stored...
    WRITE(6,'(4x,"Sigma Written to File")')
    CALL stop_clock('sigmac') 
    DEALLOCATE ( sigma_g  )
ENDIF !ionode
    call mp_barrier(inter_pool_comm)
    DEALLOCATE ( sigma    )
    RETURN
END SUBROUTINE sigma_c
