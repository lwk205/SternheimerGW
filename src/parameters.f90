  !
  !----------------------------------------------------------------
  module parameters
  !----------------------------------------------------------------
  !
  integer, parameter :: dbl = selected_real_kind(14,200)
  integer, parameter :: DP = selected_real_kind(14,200)
  INTEGER, PARAMETER :: i4b = selected_int_kind(9)

  !
  integer, parameter :: nat = 2, nk0 = 166
  integer, parameter :: nbnd = 50, nbnd_occ = 4
  !
  real(dbl), parameter :: alat = 10.26
  ! lattice parameter of silicon (5.43 A)
  ! without the factor 4 we have the volume of 8 atoms...
  real(dbl), parameter :: omega = 1080.49/4.d0 
  ! unit cell volume of silicon, bohr^3 
  real(dbl), parameter :: ecutwfc = 5.0  ! balde/tosatti: 2 Ry
  ! energy cutoff for wave functions in k-space ( in Rydbergs )
  ! 5 Ry and 40 Ry give essentially the same eps^-1(0,0,q)
  !
  ! If I use 2 Ry it bombs out since we shift the G-sphere
  ! for the refolding and most points are lost =O
  !
  real(dbl), parameter :: ecut0 = 1.1 ! NOTE: ecut0 must be SMALLER than ecut 
  ! energy cutoff for trial diagonalization of Hamiltonian (input to CG - Rydbergs )
  real(dbl), parameter :: ecuts = 1.1
  ! energy cutoff for G, W, and Sigma, Ry
  real(dbl), parameter :: eps = 1.d-10
  ! threshold for conjugate gradient convergence
  integer, parameter :: maxter = 200
  ! max number of iterations in cong grad diagonalization
  !
  ! from: Cohen & Bergstresser, PRB 141, 789 (1966)
  !
  ! diamond structure - only the symmetric form factor is nonzero, Ry
  real(dbl), parameter :: v3 = -0.21, v8 = 0.04, v11 = 0.08
  !
  ! variables for the screened Coulomb interaction
  !
  integer, parameter :: nq1 = 6, nq2 = 6, nq3 = 6
  integer, parameter :: q1 = 1, q2 = 1, q3 = 1    
  integer, parameter :: nq = nq1 * nq2 * nq3
  integer, parameter :: nksq = nq, nks = 2 * nksq  
  !
  integer, parameter :: DIRECT_IO_FACTOR = 8
  integer, parameter :: iunwfc0 = 77 ! q-grid
  integer, parameter :: iunwfc = 78  ! k and k+q grids
  integer, parameter :: iubar = 80
  integer, parameter :: iudwf = 79
  integer, parameter :: iudwfp = 81
  integer, parameter :: iudwfm = 82
  integer, parameter :: iuncoeff = 85 ! Haydock's coefficients
  integer, parameter :: iuncoul = 86  ! screened Coulomb interaction
  integer, parameter :: iungreen = 87  ! Green's function
  integer, parameter :: stdout = 6
  !
  integer, parameter :: nmax_iter = 30
  ! max n. of iterations in solve_linter
  !
  integer, parameter :: nmix_ph = 4
  ! number of previous iterations used in modified Broyden mixing
  real(DP), parameter :: tr2_ph = 1.d-10
  ! convergence threshold for dvscf
  !
  real(DP), parameter :: alpha_pv = 25.234/13.606 ! (this is 2(emax-emin)
  ! parameter for the projection over the valence manifold
  ! this is to avoid null eigenvalues in (H-e+alpha_pv*P_v)dpsi
  ! in PH it is calculated as 2*(emax-emin)
  !
  ! threshold for the iterative solution of the linear system
  ! with thresh>1d-5 the potential does not converge
  real(DP), parameter :: tr_cgsolve = 1.0d-8 
  !
  ! Heydock steps
  integer, parameter :: nstep = 50

  !
  ! frequency range for the self-energy (wsigmamin<0, sigmamax>0) - eV
  ! and for the Coulomb  (wcoulmax>0)
  real(DP), parameter :: wsigmamin = -20.d0, wsigmamax = 20.d0, deltaw = 0.5
  real(DP), parameter :: wcoulmax = 15.d0
  ! smearing for Green's function, and GW exp^ideltaw sum - Ry
  real(DP), parameter :: eta = 0.01

  !
  end module parameters
  !
