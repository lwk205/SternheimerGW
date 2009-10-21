!
!  Copyright (C) 2002-2004 PWSCF,FPMD,CPV groups
!  This file is distributed under the terms of the
!  GNU General Public License. See the file `License'
!  in the root directory of the present distribution,
!  or http://www.gnu.org/copyleft/gpl.txt .
!


#if defined (__SX4) || defined (__ORIGIN) || defined (__T3E) || defined (FUJ64) || defined (HITACHI)
#  define FLUSH
#endif

#if defined(CRAYY) || defined(__LINUX) || defined(__AIX) || defined(HITACHI) || defined(__SUN)
#  define C_POINTER  integer(kind=4)
#endif

#if defined __MAC
#  if defined __MAC64
#    define C_POINTER  integer(kind=8)
#  else
#    define C_POINTER  integer(kind=4)
#  endif
#endif

#if defined (FUJ64)|| defined (__ALPHA) || defined (__SX6) || defined(__LINUX64) || defined(__T3E)
#  define C_POINTER  integer(kind=8)
#endif

#if defined __HP
#  if defined __HP64
#    define C_POINTER  integer(kind=8)
#  else
#    define C_POINTER  integer(kind=4)
#  endif
#endif

#if defined __SGI || defined __ORIGIN
#  if defined __SGI64
#    define C_POINTER  integer(kind=8)
#  else
#    define C_POINTER  integer(kind=4)
#  endif
#endif

#if defined(__SX4)
#  define C_POINTER  real(kind=8)
#endif

#if defined(__SX4)
#  define DIRECT_IO_FACTOR 1
#elif defined(__ALPHA)
#  define DIRECT_IO_FACTOR 2
#else
#  define DIRECT_IO_FACTOR 8 
#endif

#if defined(CRAYY) || defined (__SX4) || defined (__T3E)

#  define DREAL       real
#  define DIMAG       aimag
#  define DCMPLX      cmplx

#  define DAXPY       saxpy
#  define DCOPY       scopy
#  define DDOT        sdot
#  define DGETRF      sgetrf
#  define DGETRI      sgetri
#  define DGEMV       sgemv
#  define DGEMM       sgemm
#  define DNRM2       snrm2
#  define DSCAL       sscal
#  define DSPEV       sspev
#  define DSYTRF      ssytrf
#  define DSYTRI      ssytri
#  define DSYEV       ssyev
#  define DSYGV       ssygv
#  define DSYGVX      ssygvx
#  define DSWAP       sswap
#  define ILAENV      ilaenv
#  define ZAXPY       caxpy
#  define ZCOPY       ccopy
#  define ZDOTC       cdotc
#  define ZDOTU       cdotu
#  define ZGEMM       cgemm
#  define ZGEMV       cgemv
#  define ZGESV       cgesv
#  define ZGESVD      cgesvd
#  define ZGGEV       cggev
#  define ZHEEV       cheev
#  define ZHEEVX      cheevx
#  define ZHEGV       chegv
#  define ZHEGVX      chegvx
#  define ZHETRD      CHETRD
#  define ZHPEV       chpev
#  define ZSCAL       cscal

#  define IZAMAX   icamax
#  define DYAX     syax
#  define ZSWAP    cswap
#  define ZDSCAL   csscal
#  define IDAMAX   isamax
#  define DGEMUL   sgemul
#  define DGESUB   sgesub
#  define DGER     sger
#  define DGEMTX   sgemtx
#  define DGEMX    sgemx

#  define DLAMCH   slamch
#  define DLAPY3   slapy3
#  define DZNRM2   scnrm2
#  define ZLADIV   cladiv
#  define DLAE2    slae2
#  define DLAEV2   slaev2
#  define DLANST   slanst
#  define DLAPY2   slapy2
#  define DLARTG   slartg
#  define DLASCL   slascl
#  define DLASRT   slasrt
#  define ZLASET   claset
#  define ZLASR    clasr

#  define DPOTRF   spotrf
#  define DPOTRS   spotrs

#else

#  if defined (__ALPHA) && ! defined (__LINUX)

#    define DREAL       real
#    define DCMPLX      cmplx
#    define DIMAG       imag
#    define DCONJG      conjg

#  else

#    define DREAL       dreal
#    define DCMPLX      dcmplx
#    define DIMAG       dimag

#  endif

#  if defined(ADD_BLAS_TWO_UNDERSCORES)

#    define DAXPY       daxpy__
#    define DCOPY       dcopy__
#    define DDOT        ddot__
#    define DGETRF      dgetrf__
#    define DGETRI      dgetri__
#    define DGEMV       dgemv__
#    define DGEMM       dgemm__
#    define DNRM2       dnrm2__
#    define DSCAL       dscal__
#    define DSPEV       dspev__
#    define DSYTRF      dsytrf__
#    define DSYTRI      dsytri__
#    define DSYEV       dsyev__
#    define DSYGV       dsygv__
#    define DSYGVX      dsygvx__
#    define DSWAP       dswap__
#    define ILAENV      ilaenv__
#    define ZAXPY       zaxpy__
#    define ZCOPY       zcopy__
#    define ZDOTC       zdotc__
#    define ZDOTU       zdotu__
#    define ZGEMM       zgemm__
#    define ZGEMV       zgemv__
#    define ZGESV       zgesv__
#    define ZGESVD      zgesvd__
#    define ZGGEV       zggev__
#    define ZHEEV       zheev__
#    define ZHEEVX      zheevx__
#    define ZHEGV       zhegv__
#    define ZHEGVX      zhegvx__
#    define ZHPEV       zhpev__
#    define ZSCAL       zscal__

#    define IZAMAX   izamax__
#    define DYAX     dyax__
#    define ZSWAP    zswap__
#    define ZDSCAL   zdscal__
#    define IDAMAX   idamax__
#    define DGEMUL   dgemul__
#    define DGESUB   dgesub__
#    define DGER     dger__
#    define DGEMTX   dgemtx__
#    define DGEMX    dgemx__

#    define DPOTRF   dpotrf__
#    define DPOTRS   dpotrs__

#  elif defined(ADD_BLAS_ONE_UNDERSCORE)

#    define DAXPY       daxpy_
#    define DCOPY       dcopy_
#    define DDOT        ddot_
#    define DGETRF      dgetrf_
#    define DGETRI      dgetri_
#    define DGEMV       dgemv_
#    define DGEMM       dgemm_
#    define DNRM2       dnrm2_
#    define DSCAL       dscal_
#    define DSPEV       dspev_
#    define DSYTRF      dsytrf_
#    define DSYTRI      dsytri_
#    define DSYEV       dsyev_
#    define DSYGV       dsygv_
#    define DSYGVX      dsygvx_
#    define DSWAP       dswap_
#    define ILAENV      ilaenv_
#    define ZAXPY       zaxpy_
#    define ZCOPY       zcopy_
#    define ZDOTC       zdotc_
#    define ZDOTU       zdotu_
#    define ZGEMM       zgemm_
#    define ZGEMV       zgemv_
#    define ZGESV       zgesv_
#    define ZGESVD      zgesvd_
#    define ZGGEV       zggev_
#    define ZHEEV       zheev_
#    define ZHEEVX      zheevx_
#    define ZHEGV       zhegv_
#    define ZHEGVX      zhegvx_
#    define ZHPEV       zhpev_
#    define ZSCAL       zscal_

#    define IZAMAX   izamax_
#    define DYAX     dyax_
#    define ZSWAP    zswap_
#    define ZDSCAL   zdscal_
#    define IDAMAX   idamax_
#    define DGEMUL   dgemul_
#    define DGESUB   dgesub_
#    define DGER     dger_
#    define DGEMTX   dgemtx_
#    define DGEMX    dgemx_

#    define DPOTRF   dpotrf_
#    define DPOTRS   dpotrs_

#  else

#    define DAXPY       daxpy
#    define DCOPY       dcopy
#    define DDOT        ddot
#    define DGETRF      dgetrf
#    define DGETRI      dgetri
#    define DGEMV       dgemv
#    define DGEMM       dgemm
#    define DNRM2       dnrm2
#    define DSCAL       dscal
#    define DSPEV       dspev
#    define DSYTRF      dsytrf
#    define DSYTRI      dsytri
#    define DSYEV       dsyev
#    define DSYGV       dsygv
#    define DSYGVX      dsygvx
#    define DSWAP       dswap
#    define ILAENV      ilaenv
#    define ZAXPY       zaxpy
#    define ZCOPY       zcopy
#    define ZDOTC       zdotc
#    define ZDOTU       zdotu
#    define ZGEMM       zgemm
#    define ZGEMV       zgemv
#    define ZGESV       zgesv
#    define ZGESVD      zgesvd
#    define ZGGEV       zggev
#    define ZHEEV       zheev
#    define ZHEEVX      zheevx
#    define ZHEGV       zhegv
#    define ZHEGV       zhegv
#    define ZHEGVX      zhegvx
#    define ZHPEV       zhpev
#    define ZSCAL       zscal

#    define IZAMAX   izamax
#    define DYAX     dyax
#    define ZSWAP    zswap
#    define ZDSCAL   zdscal
#    define IDAMAX   idamax
#    define DGEMUL   dgemul
#    define DGESUB   dgesub
#    define DGER     dger
#    define DGEMTX   dgemtx
#    define DGEMX    dgemx

#    define DPOTRF   dpotrf
#    define DPOTRS   dpotrs

#  endif

#endif

#if defined (__AIX) || defined (__MAC)
#  define flush  flush_
#endif

#if defined(__ABSOFT)
#  define flush  flush_
#  define getenv getenv_
#  define getarg getarg_
#  define iargc  iargc_
#endif

#ifdef __T3E
#  define iargc        ipxfargc
#  define getarg(x,y)  pxfgetarg(x,y,  ilen,ierr)
#  define getenv(x,y)  pxfgetenv(x,0,y,ilen,ierr)
#endif

#if defined(__BENCHLIB)
#  define DCOPY       scopy_t3e
#  define DGEMM       s_gemm
#  define ZGEMM       c_gemm
#endif

! #if defined (__ORIGIN) || defined (__ALTIX)
! #  define ZGEMM       zgemm3m
! #endif

#if defined(__LAM) && ( defined (__LINUX) || defined (__LINUX64) )
#define MPI_REAL8 MPI_DOUBLE_PRECISION
#endif
