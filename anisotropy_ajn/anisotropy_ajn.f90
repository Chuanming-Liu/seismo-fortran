!===============================================================================
!-------------------------------------------------------------------------------
!
!  Fortran 90/95 Source Code File
!
!-------------------------------------------------------------------------------
!===============================================================================
!
!  MODULE : anisotropy_ajn
!
!  (C) James Wookey, September 2005 - 2008
!  Department of Earth Sciences, University of Bristol
!  j.wookey@bristol.ac.uk
!
!  (C) Andy Nowacki, October 2008 - 
!  School of Earth Sciences, University of Bristol
!  andy.nowacki@bristol.ac.uk
!
!-------------------------------------------------------------------------------
!  This software is distributed in the hope that it will be useful, but WITHOUT
!  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
!  FITNESS FOR A PARTICULAR PURPOSE.
!-------------------------------------------------------------------------------
!
!     A module of functions for handling elastic constants
!
!   * Update to include CIJ_VRH and inverse by AJN,             2010/10
!     (hence the name change, to avoid confusion).
!   * Added CIJ_VRH_n for n-fold averaging                      2011/02
!   * Added CIJ_tandon_and_weng                                 2011/02
!   * Added CIJ_Au for Universal Elastic Anisotropy Index (A^U) 2011/02
!   * Added Cij2cijkl                                           2011/03
!   * Added functional form of thom, CIJ_thom                   2011/03
!   * Added functional form of isocij, CIJ_iso and updated      2011/06
!     isocij to create a full 6x6 matrix, not just the upper parts.
!   * Added CIJ_hudson                                          2011/06
!   * Added CIJ_rot90{x,y,z}                                    2011/07
!   * Added CIJ_brow_chev and associated functions for          2011/08
!     conversion from Voigt matrices to elastic vector.
!   * Added CIJ_isotropic_average for making tensors into       2011/11
!     isotropic versions of themselves.
!   * Replaced CIJ_VRH_ajn with CIJ_VRH; the former is 
!     deprecated.                                               2012/02
!   * Added CIJ_to_thom to calculate thomsen parameters for a
!     TI tensor with rotational symmetry about x3               2012/02
!   * Added CIJ_save to write out tensor as .ecs file           2012/10
!   * Added CIJ_VTI_global                                      2013/02
!===============================================================================
   module anisotropy_ajn
!===============================================================================
                                                                                
      implicit none

!  ** size constants
      integer, parameter, private :: i4 = selected_int_kind(9) ; ! long int
      integer, parameter, private :: r4 = selected_real_kind(6,37) ; ! SP
      integer, parameter, private :: r8 = selected_real_kind(15,307) ; ! DP
      
!  ** precision selector
      integer, parameter, private :: rs = r8
      
!  ** maths constants and other useful things
      real(rs), parameter, private :: pi = 3.141592653589793238462643 ;
      real(rs), parameter, private :: to_rad = 1.74532925199433e-002 ;  
      real(rs), parameter, private :: to_deg = 57.2957795130823e0 ;  
      real(rs), parameter, private :: to_km = 111.194926644559 ;      

      real(rs), parameter, private :: big_number = 10.e36 ;      

!  ** Hide the helper functions and subroutines
      private :: inverse
      
      CONTAINS

!===============================================================================
   subroutine thom(vp,vs,rho,eps,gam,del,c)
!===============================================================================
!  Output the elastic tensor given a set of Thomsen parameters.
!  Input is in m/s and kg/m^3. 
!  OUTPUT IS FULL ELASTICITY TENSOR, NOT DENSITY-NORMALISED TENSOR!!!!
!  Remember to normalise by density if using other routines which require that.

   implicit none
      real(rs),intent(out) :: c(6,6)
      real(rs),intent(in)  :: vp,vs,rho
      real(rs),intent(in)  :: eps,gam,del
      real(rs) :: term,btm,ctm,dsrmt
      integer  :: i,j
      
      c = 0.

      c(3,3) = vp*vp*rho
      c(4,4) = vs*vs*rho
      c(1,1) = c(3,3)*(2.0*eps +1.0)
      c(6,6) = c(4,4)*(2.0*gam +1.0)

      btm = 2.0*c(4,4)
      term = c(3,3) - c(4,4)
      ctm = c(4,4)*c(4,4) - (2.0*del*c(3,3)*term + term*term)
      dsrmt = (btm*btm - 4.0*ctm)
      if (dsrmt.lt.0.0) then
         write(0,*) 'WARNING: S-velocity too high', &
       ' or delta too negative for Thomsen routine', &
       ' Re-input parameters'
         stop
      endif   
      c(1,3) = -btm/2.0 + sqrt(dsrmt)/2.0 

      c(1,2) = c(1,1) - 2.0*c(6,6)
      c(2,3) = c(1,3)
      c(5,5) = c(4,4)
      c(2,2) = c(1,1)

!     Make symmetrical
      do i=1,6; do j=1,6; c(j,i) = c(i,j); enddo; enddo
     
      return
   end subroutine thom
!===============================================================================

!===============================================================================
   function CIJ_thom(vp,vs,rho,eps,gam,del)
!===============================================================================
!  Functional form of the subroutine thom

     implicit none
     real(rs),intent(in) :: vp,vs,rho,eps,gam,del
     real(rs)            :: CIJ_thom(6,6)
     
     call thom(vp,vs,rho,eps,gam,del,CIJ_thom)
     
     return
   end function CIJ_thom
!-------------------------------------------------------------------------------

!===============================================================================
   function CIJ_global_VTI(vp,vs,rho,xi,phi,eta)
!===============================================================================
!  Output the elastic tensor given a set of radial anisotropy parameters
!  as used typically in global seismology.  Average velocities are given by:
!        15*rho*<Vp>^2 = 3*C + (8 + 4*eta)*A + 8*(1 - eta)*L
!        15*rho*<Vs>^2 =   C + (1 - 2*eta)*A + (6 + 4*eta)*L + 5*N
!     vp:   Voigt average P wave velocity
!     vs:   Voigt average shear wave velocity
!     rho:  Density
!     xi:   (Vsh^2/Vsv^2) of horizontal waves
!     phi:  (Vpv^2/Vph^2)
!     eta:  C13/(C11 - 2*C44)
!  Input is in m/s and kg/m^3
!  Output is UNNORMALISED ELASTICITY TENSOR, not density-normalised

      implicit none
      real(rs) :: CIJ_global_VTI(6,6)
      real(rs),intent(in) :: vp,vs,rho,xi,phi,eta
      real(rs) :: C12,A,C,F,L,N
      real(rs),parameter :: O = 0._rs  ! Zero
      
      ! Love parameters from Voigt isotropic velocities and dimensionless parameters
      L = 15._rs*rho*((3._rs*phi+8._rs+4._rs*eta)*vs**2 - &
            (phi+1._rs-2._rs*eta)*vp**2) &
         / ((6._rs+4._rs*eta+5._rs*xi)*(3._rs*phi+8._rs+4._rs*eta) &
            - 8._rs*(phi+1._rs-2._rs*eta)*(1._rs-eta))
      
      A = (15._rs*rho*vp**2 - 8._rs*(1._rs-eta)*L) &
         / (3._rs*phi + 8._rs + 4._rs*eta)
      
      F = eta*(A - 2._rs*L)
      C = phi*A
      N = xi*L
      C12 = A - 2._rs*N
      
      CIJ_global_VTI = reshape( &
            (/ A , C12, F, O, O, O, &
              C12,  A , F, O, O, O, &
               F ,  F , C, O, O, O, &
               O ,  O , O, L, O, O, &
               O ,  O , O, O, L, O, &
               O ,  O , O, O, O, N  /), (/6,6/))
   end function CIJ_global_VTI
!-------------------------------------------------------------------------------      

!===============================================================================
   function CIJ_panning_VTI(vp,vs,rho,xi,phi)
!===============================================================================
!  Output the elastic tensor given a set of radial anisotropy parameters
!  as used by Panning and Romanowicz in their global tomography.  They assume
!  that eta ~ 1 and A ~ C to simplify the expression for Voigt average velocities
!  to:
!        <Vp>^2 = (1/5)*(Vpv^2 + 4*Vph^2)
!        <Vs>^2 = (1/3)*(Vsh^2 + 2*Vsv^2)
!     vp:   'Average' P-wave velocity
!     vs:   'Average' S-wave velocity
!     rho:  Density
!     xi,phi:  Dimensionaless radial anisotropy parameters
!  Input is in m/s and kg/m^3
!  Output is UNNORMALISED ELASTICITY TENSOR, not density normalised

      implicit none
      real(rs) :: CIJ_panning_VTI(6,6)
      real(rs),intent(in) :: vp,vs,rho,xi,phi
      real(rs) :: A,C,F,L,N,C12
      real(rs),parameter :: O = 0._rs
      
      ! Love parameters from simplified Voigt isotropic average velocities
      L = rho*3._rs*vs**2/(2._rs + xi)
      N = xi*L
      A = rho*5._rs*vp**2/(4._rs + phi)
      C = phi*A
      F = A - 2._rs*L
      C12 = A - 2._rs*N
      
      CIJ_panning_VTI = reshape( &
            (/ A , C12, F, O, O, O, &
              C12,  A , F, O, O, O, &
               F ,  F , C, O, O, O, &
               O ,  O , O, L, O, O, &
               O ,  O , O, O, L, O, &
               O ,  O , O, O, O, N  /), (/6,6/))

   end function CIJ_panning_VTI      
!-------------------------------------------------------------------------------      

!===============================================================================
   subroutine CIJ_VTI2thom(C,rho,eps,gam,del)
!===============================================================================
!  Given a normalised elasticity tensor and density, return the Thomsen (1986)
!  parameters.  The tensor must be VTI, symmetrical about x3.
      implicit none
      real(rs),intent(in) :: C(6,6),rho
      real(rs),intent(out) :: eps,gam,del
      real(rs) :: tol
      
!  Test for correct tensor input
      tol = 1._rs  ! Tolerance in tensor
      if (abs(C(1,1)-C(2,2)) > tol .or. abs(C(4,4)-C(5,5)) > tol .or. &
          abs(C(2,3)-C(1,3)) > tol .or. &
          abs(C(1,4)) > tol .or. abs(C(1,5)) > tol .or. abs(C(1,6)) > tol .or. &
          abs(C(2,4)) > tol .or. abs(C(2,5)) > tol .or. abs(C(2,6)) > tol .or. &
          abs(C(3,4)) > tol .or. abs(C(3,5)) > tol .or. abs(C(3,6)) > tol .or. &
          abs(C(4,5)) > tol .or. abs(C(4,6)) > tol .or. abs(C(5,6)) > tol) then
         write(0,'(2a)') 'anisotropy_ajn: CIJ_to_thom: Error: Tensor not in correct form. ',&
                         'Require TI with hexad // x3.'
         stop
      endif
      
      eps = (C(1,1) - C(3,3))/(2._rs*C(3,3))
      gam = (C(6,6) - C(4,4))/(2._rs*C(4,4))
      del = ((C(1,3)+C(4,4))**2-(C(3,3)-C(4,4))**2)/(2._rs*C(3,3)*(C(3,3)-C(4,4)))
   
   end subroutine CIJ_VTI2thom
!-------------------------------------------------------------------------------

!===============================================================================
   subroutine isocij(vp,vs,C)
!===============================================================================
!
!  Generate a set of elastic constants from isotropic velocities  
!  (input velocities in m/s)
!-------------------------------------------------------------------------------
      implicit none
      real(rs) :: C(6,6) ! Voigt notation matrix
      real(rs) :: vp,vs
      integer  :: i,j
      
      C(:,:) = 0.0

      C(3,3) = vp**2
      C(4,4) = vs**2

      C(1,1) = C(3,3) ; C(2,2) = C(3,3)
      C(5,5) = C(4,4) ; C(6,6) = C(4,4)
      C(1,2) = (C(3,3)-2.d0*C(4,4))
      C(1,3) = C(1,2) ; C(2,3) = C(1,2)
      
      do i=1,6; do j=1,6; C(j,i) = C(i,j); enddo; enddo
      
      return
   end subroutine isocij
!-------------------------------------------------------------------------------

!===============================================================================
   function CIJ_iso(vp,vs)
!===============================================================================
!  Functional form of the subroutine isocij
      implicit none
      real(rs),intent(in) :: vp,vs
      real(rs)            :: CIJ_iso(6,6)
      
      call isocij(vp,vs,CIJ_iso)
      
      return
   end function CIJ_iso
!-------------------------------------------------------------------------------  
   
!===============================================================================
   subroutine CIJ_load_list(fname,nin,n,x,C,rho)
!===============================================================================
!
!  Load a set of elastic constants varying with x (first column in file) 
! 
!  Outputs
!  x is the independent variable (the first column in the file, 
!  of length n) 
!  C is an array 6*6*n where n is the number of tensors loaded 
!  rho is a vector of length n, the last column in the file
!  currently, only 21 constant elastic files can be loaded. Lines in the file
!  should be of the form:
! 
!  x, c11,c12,...,c16,c22,...,c26,c33,...,c66,rho 
!
!-------------------------------------------------------------------------------
      implicit none
      integer :: nin,n
      real(rs) :: C(6,6,nin) ! Voigt notation matrix
      real(rs) :: Cin(21)
      real(rs) :: ec, rho(nin),x(nin)
      
      integer :: ierr,ioflag ! error flags
      integer :: i,j,itensor,icnt
      
      character (len = 80) :: fname
!  ** open the EC file and read in elastic constants      
      C(:,:,:) = 0.0 

      open(99,file=fname, iostat=ioflag, status='old')
      if (ioflag /= 0) then
         stop 'File not found'
      endif
      
      itensor=1
      do ! forever
         read(99,*,iostat=ioflag) x(itensor),(Cin(i),i=1,21),rho(itensor)
         if (ioflag < 0 ) exit ! EOF
         icnt = 0
         do i=1,6
            do j=i,6
               icnt=icnt+1
               C(i,j,itensor) = Cin(icnt)
               C(j,i,itensor) = Cin(icnt)
            enddo   
         enddo
         itensor=itensor + 1
      enddo
      
      n=itensor-1
      
      close(99)

      return
   end subroutine CIJ_load_list
!===============================================================================


!===============================================================================
   subroutine CIJ_load(fname,C,rho)
!===============================================================================
!
!  Load a set of elastic constants  
!
!-------------------------------------------------------------------------------
      implicit none
      real(rs) :: C(6,6) ! Voigt notation matrix
      real(rs) :: ec, rho      
      integer :: ioflag ! error flags
      integer :: i,j,nec
      
!      character (len = 80) :: fname
      character(*) :: fname
!  ** open the EC file and read in elastic constants      
      C(:,:) = 0.0 ; nec = 0

      open(unit=99,file=fname, iostat=ioflag, status='old')
      if (ioflag /= 0) then
         stop 'File not found'
      endif
      
      do ! forever
         read(99,*,iostat=ioflag) i,j,ec
         if (ioflag > 0) then ! Problem reading
            write(0,'(a)') 'anisotropy_ajn: CIJ_load: problem reading .ecs file.'
            stop
         endif
         if (ioflag < 0) exit ! EOF
         nec = nec + 1 ;
         if (i==7 .and. j==7) then
            rho = ec
         else   
            C(i,j) = ec ; C(j,i) = ec ; 
         endif   
      enddo

      nec = nec - 1 ! account for density
!      close(99)

!  ** check for a valid number of elastic constants: ie 2, 9, 13 or 21      
      if (nec/=2 .and. nec/=9 .and. nec/=13 .and. nec/=21) then
         write(0,*) 'Invalid number of elastic constants; need 2, 9, 13 or 21'
         stop 
      endif

!  ** fill out the Cij matrix if isotropic
      if (nec == 2) then
         C(1,1) = C(3,3) ; C(2,2) = C(3,3)
         C(5,5) = C(4,4) ; C(6,6) = C(4,4)
         C(1,2) = (C(3,3)-2.d0*C(4,4))
         C(1,3) = C(1,2) ; C(2,3) = C(1,2) ;
      endif   
      
!   ** Make symmetrical
      do i=1,6
         do j=i,6
            C(j,i) = C(i,j)
         enddo
      enddo

      close(99)
      
      return
   end subroutine CIJ_load
!===============================================================================

!===============================================================================
  subroutine CIJ_save(fname,C,rho)
!===============================================================================
!
!  Save a set of elastic constants
!
!-------------------------------------------------------------------------------
      implicit none
      real(rs),intent(in) :: C(6,6),rho
      character(len=*),intent(in) :: fname
      integer :: i,j
      
!  ** Write constants out in format i j C(i,j)
      open(99,file=fname)
      do i=1,6
         do j=i,6
            write(99,*) i,j,C(i,j)
         enddo
      enddo
!  ** Density
      i = 7
      j = 7
      write(99,*) i,j,rho
      close(99)

   end subroutine CIJ_save
!-------------------------------------------------------------------------------

!===============================================================================
   subroutine CIJ_rot3(C,alp,bet,gam,CR)
!===============================================================================
!  
!  Rotate an elastic constant matrix in 3D, by three angles:
!
!  alpha = clockwise rotation about the 1-axis, looking at origin (~ yaw)
!          (+ve from 3 -> 2)
!  beta  = clockwise rotation about the 2-axis, looking at origin (~ dip)
!          (+ve from 1 -> 3)
!  gamma = clockwise rotation about the 3-axis, looking at origin (~ azimuth)
!          (+ve from 2 -> 1)
!
!  The rotations are applied in this order
!    
!  Subroutine is based in part on code by David Mainprice
!
!-------------------------------------------------------------------------------
      implicit none
      
      real(rs) :: C(6,6), CR(6,6) ! Voigt notation matrix
      real(rs) :: alp,bet,gam ! rotation (clockwise) about 1,2,3 axis respectively
      real(rs) :: a,b,g     
      real(rs) :: R(3,3), D(6,6), R1(3,3), R2(3,3), R3(3,3), R21(3,3)
      
      integer :: i,j,k,l,m,n,lp,lq,lt
            
      real(rs) :: x,y
      
      integer :: l1(6), l2(6), ijkl(3,3)
      data ((ijkl(i,j),j=1,3),i=1,3)/1,6,5,6,2,4,5,4,3/
      data (l1(j),j=1,6)/1,2,3,2,3,1/
      data (l2(j),j=1,6)/1,2,3,3,1,2/
      
!  ** clone the Cij matrix      
      CR(:,:) = 0._rs
!  ** build the individual rotation matrices
      a = alp * pi/180._rs
      b = bet * pi/180._rs
      g = gam * pi/180._rs

      R1(1,1) =  1.     ; R1(1,2) =  0.     ; R1(1,3) =  0.
      R1(2,1) =  0.     ; R1(2,2) =  cos(a) ; R1(2,3) =  sin(a)
      R1(3,1) =  0.     ; R1(3,2) = -sin(a) ; R1(3,3) =  cos(a)

      R2(1,1) =  cos(b) ; R2(1,2) =  0.     ; R2(1,3) = -sin(b)
      R2(2,1) =  0.     ; R2(2,2) =  1.     ; R2(2,3) =  0.
      R2(3,1) =  sin(b) ; R2(3,2) =  0.     ; R2(3,3) =  cos(b)

      R3(1,1) =  cos(g) ; R3(1,2) =  sin(g) ; R3(1,3) =  0.
      R3(2,1) = -sin(g) ; R3(2,2) =  cos(g) ; R3(2,3) =  0.
      R3(3,1) =  0.     ; R3(3,2) =  0.     ; R3(3,3) =  1.

!  ** build the compound matrix
      R21 = matmul(R2,R1)             
      R = matmul(R3,R21)

!  ** rotate elastic constants form crystal to spacial coordinates
!  ** cijkl=rip*rjq*rkr*rls*cpqrs
      do m=1,6
         i = l1(m)
         j = l2(m)
! **  compute lower diagonal
         do n=1,m
            k = l1(n)
            l = l2(n)
            x = 0.0_rs
            do lp=1,3
               y = 0.0_rs
               do lq=1,3
                  lt = ijkl(lp,lq)
                  y = y + R(j,lq)* &
                     (R(k,1)*(R(l,1)*C(lt,1) + R(l,2)*C(lt,6) + R(l,3)*C(lt,5)) &
                    + R(k,2)*(R(l,1)*C(lt,6) + R(l,2)*C(lt,2) + R(l,3)*C(lt,4)) &
                    + R(k,3)*(R(l,1)*C(lt,5) + R(l,2)*C(lt,4) + R(l,3)*C(lt,3)))
               enddo   
               x = x + R(i,lp)*y
            enddo
            CR(m,n) = x
! **    copy to upper diagonal
            CR(n,m) = x
         enddo
      enddo
      
      return
   end subroutine CIJ_rot3
!-------------------------------------------------------------------------------

!===============================================================================
   function CIJ_rot90x(C)
!===============================================================================
!  Rotates 6x6 Voigt tensors about the 1-axis by 90 degrees (clockwise, looking
!  at origin): for this special case we can simply subsitute values for speed.
      implicit none
      real(rs),intent(in) :: C(6,6)
      real(rs)            :: CIJ_rot90x(6,6),R(6,6)
      integer             :: i,j
      
   R(1,1)=C(1,1); R(1,2)=C(1,3) ; R(1,3)=C(1,2) ; R(1,4)=-C(1,4); R(1,5)=-C(1,6); R(1,6)=C(1,5)
   R(2,2)=C(3,3); R(2,3)=C(2,3) ; R(2,4)=-C(3,4); R(2,5)=-C(3,6); R(2,6)=C(3,5)
   R(3,3)=C(2,2); R(3,4)=-C(2,4); R(3,5)=-C(2,6); R(3,6)=C(2,5)
   R(4,4)=C(4,4); R(4,5)=C(4,6) ; R(4,6)=-C(4,5)
   R(5,5)=C(6,6); R(5,6)=-C(5,6)
   R(6,6)=C(5,5)
      
      do i=1,6; do j=1,6; R(j,i) = R(i,j); enddo; enddo
      CIJ_rot90x = R
      
      return
   end function CIJ_rot90x
!-------------------------------------------------------------------------------

!===============================================================================
   function CIJ_rot90y(C)
!===============================================================================
!  Rotates 6x6 Voigt tensors about the 2-axis by 90 degrees (clockwise, looking
!  at origin): for this special case we can simply subsitute values for speed.
      implicit none
      real(rs),intent(in) :: C(6,6)
      real(rs)            :: CIJ_rot90y(6,6),R(6,6)
      integer             :: i,j
      
   R(1,1)=C(3,3); R(1,2)=C(2,3) ; R(1,3)=C(1,3) ; R(1,4)=C(3,6) ; R(1,5)=-C(3,5); R(1,6)=-C(3,4)
   R(2,2)=C(2,2); R(2,3)=C(1,2) ; R(2,4)=C(2,6) ; R(2,5)=-C(2,5); R(2,6)=-C(2,4)
   R(3,3)=C(1,1); R(3,4)=C(1,6) ; R(3,5)=-C(1,5); R(3,6)=-C(1,4)
   R(4,4)=C(6,6); R(4,5)=-C(5,6); R(4,6)=-C(4,6)
   R(5,5)=C(5,5); R(5,6)=C(4,5)
   R(6,6)=C(4,4)
      
      do i=1,6; do j=1,6; R(j,i) = R(i,j); enddo; enddo
      CIJ_rot90y = R
            
      return
   end function CIJ_rot90y
!-------------------------------------------------------------------------------

!===============================================================================
   function CIJ_rot90z(C)
!===============================================================================
!  Rotates 6x6 Voigt tensors about the 3-axis by 90 degrees (clockwise, looking
!  at origin): for this special case we can simply subsitute values for speed.
      implicit none
      real(rs),intent(in) :: C(6,6)
      real(rs)            :: CIJ_rot90z(6,6),R(6,6)
      integer             :: i,j
      
   R(1,1)=C(2,2); R(1,2)=C(1,2) ; R(1,3)=C(2,3) ; R(1,4)=-C(2,5); R(1,5)=C(2,4); R(1,6)=-C(2,6)
   R(2,2)=C(1,1); R(2,3)=C(1,3) ; R(2,4)=-C(1,5); R(2,5)=C(1,4) ; R(2,6)=-C(1,6)
   R(3,3)=C(3,3); R(3,4)=-C(3,5); R(3,5)=C(3,4) ; R(3,6)=-C(3,6)
   R(4,4)=C(5,5); R(4,5)=-C(4,5); R(4,6)=C(5,6)
   R(5,5)=C(4,4); R(5,6)=-C(4,6)
   R(6,6)=C(6,6)
      
      do i=1,6; do j=1,6; R(j,i) = R(i,j); enddo; enddo
      CIJ_rot90z = R
            
      return
   end function CIJ_rot90z
!-------------------------------------------------------------------------------


!===============================================================================
   subroutine effective_splitting(fast1,tlag1,fast2,tlag2,f,fast_eff,tlag_eff)
!===============================================================================
!
!  Calculate the effective splitting for two anisotropic layers using the
!  theory of Silver and Savage (1994). Implicitly assumes spol=0 (!)
!
!===============================================================================
      implicit none
!  ** arguments (inputs)
      real(rs) :: tlag1,fast1 ! layer 1 splitting parameters (s,deg)
      real(rs) :: tlag2,fast2 ! layer 2 splitting parameters (s,deg)
      real(rs) :: f ! dominant frequency
!  ** arguments (outputs)
      real(rs) :: tlag_eff,fast_eff ! calculated effective splitting parameters
!  ** locals      
      real(rs) :: w ! angular frequency
      real(rs) :: th1,th2,al1,al2,ap,app,Cc,Cs,ala,tha! see Silver and Savage (1994)

      w = 2. * pi * f ;

      th1 = w * tlag1 / 2. ;
      th2 = w * tlag2 / 2. ;

      al1 = 2.*fast1 * pi/180.0;
      al2 = 2.*fast2 * pi/180.0;
   
      ap = cos(th1)*cos(th2) - sin(th1)*sin(th2)*cos(al2-al1) ;
      app = -sin(th1)*sin(th2)*sin(al2-al1) ;
      Cc = cos(th1)*sin(th2)*cos(al2) + cos(th2)*sin(th1)*cos(al1) ;
      Cs = cos(th1)*sin(th2)*sin(al2) + cos(th2)*sin(th1)*sin(al1) ;

      ala = atan ( (app**2.+Cs**2.) / (app*ap + Cs*Cc) ) ;
      tha = atan ( (app) / (Cs*cos(ala)-Cc*sin(ala)) ) ;
      
      fast_eff = (ala*180./pi) / 2.
      tlag_eff = 2.*tha/w
      
!  ** if tlag_eff is negative, add 90 to fast_eff and abs tlag_eff
!  ** (just swapping descriptions of the fast and slow)

      if (tlag_eff < 0.0 ) then
         fast_eff = fast_eff + 90.0
         call unwind_pm_90(fast_eff) ! unwind angle
         tlag_eff = abs(tlag_eff)
      endif    
      
      return
   end subroutine effective_splitting
!===============================================================================

!===============================================================================
   subroutine unwind_pm_90(angle)
!===============================================================================
!
!  unwind an angle to be in the range -90 -- 90 degrees
!
!     angle :  (I/O) angle to unwind
!
      implicit none
      real(rs) :: angle

      do ! forever
         if (angle >= -90.0 .and. angle < 90.0) exit
         if (angle >= 90.0) angle = angle - 180.0
         if (angle < -90.0) angle = angle + 180.0      
      enddo
      
      return
   end subroutine unwind_pm_90
!===============================================================================

!===============================================================================
   subroutine unwind_pm_180(angle)
!===============================================================================
!
!  unwind an angle to be in the range 0-180 degrees
!
!     angle :  (I/O) angle to unwind
!
      implicit none
      real(rs) :: angle

      do ! forever
         if (angle >= .0 .and. angle < 180.0) exit
         if (angle >= 180.0) angle = angle - 180.0
         if (angle < -180.0) angle = angle + 180.0      
      enddo
      
      return
   end subroutine unwind_pm_180
!===============================================================================

!===============================================================================
   subroutine CIJ_VRH(VF1,C1,rh1,VF2,C2,rh2,Cave,rhave)
!===============================================================================
! Calculate the Voigt-Reuss-Hill average of two tensors and densities
! f90 version by AJN from MATLAB code by JW 2010/10
!
      implicit none
      
      real(rs)   :: VF1,VF2,rh1,rh2,rhave,C1(6,6),C2(6,6),Cave(6,6)
      real(rs)   :: C1_inv(6,6),C2_inv(6,6),reuss_inv(6,6)
      real(rs)   :: voigt(6,6),reuss(6,6)

!  Normalise the volume fractions to sum to unity
      VF1 = VF1 / (VF1 + VF2)   ;  VF2 = VF2 / (VF1 + VF2)
      
!  Find inverse of Cs
      call inverse(6,6,C1,C1_inv)
      call inverse(6,6,C2,C2_inv)
      
!  Initialise matrices to 0s
      voigt = 0.   ;   reuss = 0.
      rhave = 0.
      
      voigt = C1*VF1 + C2*VF2
      reuss = C1_inv*VF1 + C2_inv*VF2
      call inverse(6,6,reuss,reuss_inv)
      rhave = rh1*VF1 + rh2*VF2
      
      Cave = (voigt + reuss_inv) /2.
      
   end subroutine CIJ_VRH
!------------------------------------------------------------------------------

!===============================================================================
   subroutine CIJ_VRH_ajn(VF1,C1,rh1,VF2,C2,rh2,Cave,rhave)
!===============================================================================
!  Deprecated synonym for CIJ_VRH
      implicit none
      real(rs),intent(in) :: VF1,C1(6,6),rh1,VF2,C2(6,6),rh2
      real(rs),intent(out) :: Cave(6,6),rhave
      
      call CIJ_VRH(VF1,C1,rh1,VF2,C2,rh2,Cave,rhave)
   end subroutine CIJ_VRH_ajn
!-------------------------------------------------------------------------------

!==============================================================================
   subroutine CIJ_VRH_n(n,VF_in,C_in,rh_in,Cave,rhave)
!==============================================================================
! Calculate the Voigt-Reuss-Hill average of n tensors and densities
! VF and rh are column vectors of length n
! C is a tensor dimensions (n,6,6)
! AJN 2011/02
!
      implicit none
      
      integer,intent(in)   :: n
      integer              :: i
      real(rs),intent(in)  :: VF_in(n),C_in(n,6,6),rh_in(n)
      real(rs),intent(out) :: Cave(6,6),rhave
      real(rs)             :: VF(n),C(n,6,6),C_inv(n,6,6),rh(n),&
                              voigt(6,6),reuss(6,6),reuss_inv(6,6)
      
!  Normalise the volume fractions to sum to unity
      VF = VF_in / sum(VF_in)
      
!  Find inverse of Cs
      C = C_in
      rh = rh_in
      do i=1,n
         call inverse(6,6,C(i,:,:),C_inv(i,:,:))
      enddo

!  Initialise matrices to 0s
      voigt = 0.   ;  reuss = 0.   ;   rhave = 0.   ;   Cave = 0.
      
      do i=1,n
         voigt = voigt + VF(i) * C(i,:,:)
         reuss = reuss + VF(i) * C_inv(i,:,:)
         rhave = rhave + VF(i) * rh(i)
      enddo

      call inverse(6,6,reuss,reuss_inv)
      
      Cave = (voigt + reuss_inv) / 2.
      
      return
      
   end subroutine CIJ_VRH_n
!------------------------------------------------------------------------------

!===============================================================================
   subroutine CIJ_Voigt_av(VF_in,C_in,rh_in,Cave,rhave)
!===============================================================================
!  Calculate the Voigt average of n tensors and densities
!  IO as for CIJ_VRH_n
      implicit none
      real(rs),intent(in) :: VF_in(:), C_in(:,:,:), rh_in(:)
      real(rs),intent(out) :: Cave(6,6), rhave
      integer :: i,n
      real(rs),allocatable :: VF(:)
      
!  Get size of arrays and check they're consistent
      n = size(VF_in)
      if (size(C_in,1) /= n .or. size(rh_in) /= n) then
         write(0,'(a)') 'anisotropy_ajn: CIJ_Voigt_av: input VF, C and rh must be same length.'
         stop
      elseif (size(C_in,2) /= 6 .or. size(C_in,3) /= 6) then
         write(0,'(a)') 'anisotropy_ajn: CIJ_Voigt_av: C must be nx6x6 array.'
         stop
      endif
      
!  Allocate space for arrays
      allocate(VF(n))
      
!  Normalise the volume fractions to sum to unity
      VF = VF_in / sum(VF_in)
      
!  Construct Voigt average
      Cave = 0.  ;  rhave = 0.
      do i=1,n
         Cave = Cave + VF(i)*C_in(i,:,:)
         rhave = rhave + VF(i)*rh_in(i)
      enddo
      
      deallocate(VF)
      
   end subroutine CIJ_Voigt_av
!-------------------------------------------------------------------------------

!===============================================================================
   subroutine CIJ_Reuss_av(VF_in,C_in,rh_in,Cave,rhave)
!===============================================================================
!  Calculate the Reuss average of n tensors and densities
!  IO as for CIJ_VRH_n
      implicit none
      real(rs),intent(in) :: VF_in(:), C_in(:,:,:), rh_in(:)
      real(rs),intent(out) :: Cave(6,6), rhave
      integer :: i,n
      real(rs),allocatable :: VF(:)
      real(rs) :: S(6,6), S_in(6,6), C_temp(6,6)
      
!  Get size of arrays and check they're consistent
      n = size(VF_in)
      if (size(C_in,1) /= n .or. size(rh_in) /= n) then
         write(0,'(a)') 'anisotropy_ajn: CIJ_Voigt_av: input VF, C and rh must be same length.'
         stop
      elseif (size(C_in,2) /= 6 .or. size(C_in,3) /= 6) then
         write(0,'(a)') 'anisotropy_ajn: CIJ_Voigt_av: C must be nx6x6 array.'
         stop
      endif
      
!  Allocate space for arrays
      allocate(VF(n))
      
!  Normalise the volume fractions to sum to unity
      VF = VF_in / sum(VF_in)
      
!  Construct Reuss average
      Cave = 0.  ;  S = 0.;  rhave = 0.
      do i=1,n
         !  Find compliance from input stiffness
         C_temp = C_in(i,:,:)
         call inverse(6,6,C_temp,S_in)
         S = S + VF(i)*S_in
         rhave = rhave + VF(i)*rh_in(i)
      enddo
      
!  Find stiffness from compliance
      call inverse(6,6,S,Cave)
      
      deallocate(VF)
      
   end subroutine CIJ_Reuss_av
!-------------------------------------------------------------------------------


!===============================================================================
   subroutine CIJ_hudson(vp,vs,rho,a,phi,vpi,vsi,rhoi,Cout,rhout)
!===============================================================================
!  Calculates the effective elastic constants using the theory of Hudson (1980)
!  for a series of penny-shaped cracks in an isotropic medium.
!  Taken from http://srb.stanford.edu/docs/theses/SRB_66_JUN98_Teng.pdf
!
!  Input:
!     vp,vs,rho:    isotropic medium parameters, in m/s, kg/m^3
!     vpi,vsi,rhoi: isotropic crack parameters:     "      "
!     a:            aspect ratio of penny-shaped cracks (<1)
!     phi:          volume fraction of cracks
!
!  Output:
!     Cout:  elastic constants (density-normalised)
!     rhout: effective density
!
!  The axis of rotational symmetry is parallel to the 3-axis (i.e., VTI in 1-2 plane).
!
!  The theory is only valid where e < 0.1 (i.e. phi > 0.4*a), so small aspect
!  ratios must be accompanied by small volume fractions.

   implicit none
      real(rs),intent(in) :: vp,vs,rho,a,phi,vpi,vsi,rhoi
      real(rs),intent(out) :: Cout(6,6),rhout
      real(rs) :: mu,lam,K,C0(6,6),mui,lami,ki,M,kappa,U1,U3,e,C1(6,6)
      integer :: i,j
      
!  Weighted average of densities
      rhout = (1._rs-phi)*rho + phi*rhoi
      
!  Properties of isotropic medium
      mu = rho*vs**2
      lam = rho*(vp**2 - 2*vs**2)
      K = rho*vp**2 - (4._rs/3._rs)*mu
      C0 = 0._rs
      C0(1,1) = rho*vp**2
      C0(2,2) = C0(1,1)
      C0(3,3) = C0(1,1)
      C0(4,4) = rho*vs**2
      C0(5,5) = C0(4,4)
      C0(6,6) = C0(4,4)
      C0(1,3) = rho*(vp**2 - 2._rs*vs**2)
      C0(2,3) = C0(1,3)
      C0(1,2) = C0(1,3)
      do i=1,6; do j=1,6; C0(j,i) = C0(i,j); enddo; enddo
      
!  Properties of isotropic inclusions
      mui = rhoi*vsi**2
      lami = rhoi*(vpi**2 - 2._rs*vsi**2)
      Ki = rhoi*vpi**2 - (4._rs/3._rs)*mui
      
      M = 4*mui*(lam + 2._rs*mu)/(pi*a*mu*(3._rs*lam + 4._rs*mu))
      kappa = (Ki + 4._rs*mui/3._rs)*(lam + 2._rs*mu)/(pi*a*mu*(lam + mu))
      
      U1 = 16._rs*(lam + 2._rs*mu)/(3._rs*(3._rs*lam + 4._rs*mu)*(1._rs + M))
      U3 = 4._rs*(lam + 2._rs*mu)/(3._rs*(lam + mu)*(1._rs + kappa))
      
!  Calculate e and check it's valid; carry on with calculation, but warn.
      e = 3._rs*phi/(4._rs*pi*a)
      if (e > 0.1_rs) then
         write(0,'(a)') &
'CIJ_hudson: warning: The theory of Hudson is only valid for e (crack density) < 0.1.  Output values will not be realistic.'
      endif
      
!  Construct first-order correction terms for matrix
      C1 = 0._rs
      C1(1,1) = -lam**2*e*U3/mu
      C1(1,3) = -lam*(lam + 2._rs*mu)*e*U3/mu
      C1(3,3) = -(lam + 2._rs*mu)**2*e*U3/mu
      C1(4,4) = -mu*e*U1
      C1(6,6) = 0
      
      C1(2,2) = C1(1,1)
      C1(5,5) = C1(4,4)
      C1(2,3) = C1(1,3)
      C1(1,2) = C1(1,3)
!  Make symmetrical
      do i=1,6; do j=1,6; C1(j,i) = C1(i,j); enddo; enddo
      
      Cout = (C0 + C1)/rhout
   
      return
   
   end subroutine CIJ_hudson
!-------------------------------------------------------------------------------

!==============================================================================
   subroutine CIJ_tandon_and_weng(vp_in,vs_in,rho_in,del_in,c_in,vpi_in,vsi_in,&
                                  rhoi_in,C_out,rh_out)
!==============================================================================
!  Calculates the elatic constants using the theory of Tandon & Weng (1984)
!  for an isotropic matrix (vp,vs,rho) and inclusions (vpi,vsi,rhoi) aligned with 
!  rotational symmetry axis // 1-axis.
!
!  Taken from MATLAB code tandon_and_weng by James Wookey, which is
!  based on FORTRAN code by Mike Kendall, and converted back.
!
!  Input:
!    vp,vs,rho:    isotropic medium parameters, in m/s, kg/m^3
!    vpi,vsi,rhoi: inclusions parameters,           "      "
!    del is aspect ratio of spheroidal inclusions: <1=oblate, >1=prolate
!    c is volume fraction of inclusions (0<=c<=1)
!
!  Output:
!    C_out:        ecs, density normalised
!    rh_out:       effective density

      implicit none
     
     real(rs),intent(in)   :: vp_in,vs_in,rho_in,del_in,c_in,vpi_in,vsi_in,rhoi_in
     real(rs),intent(out)  :: C_out(6,6),rh_out
     real(rs)              :: amu,amui,alam,alami,bmi,bmps,E0,anu,amu12,amu23,anu31,&
                        anum,denom,aK23,anu12tst,CC(6,6),rh
     real(rs)              :: t1,t2,t3,t4,t5,D1,D2,D3,acshdel,g
     real(rs)              :: s11,s12,s13,s14,s15,s16,&
                              s21,s22,s23,s24,s25,s26,&
                              s31,s32,s33,s34,s35,s36,&
                              s41,s42,s43,s44,s45,s46,&
                              s51,s52,s53,s54,s55,s56,&
                              s61,s62,s63,s64,s65,s66
     real(rs)              :: A,A1,A2,A3,A4,A5,B1,B2,B3,B4,B5,E11,E22
     integer               :: i,j
   
!  Check input parameters
      if (c_in < 0. .or. c_in > 1.) then
         write(0,'(a)') &
       'CIJ_tandon_and_weng: Volume fraction of inclusions must be between 0 and 1.'
         stop
      endif
      if (del_in == 1.) then
         write(0,'(a)') 'CIJ_tandon_and_weng: Aspect ratio of inclusions cannot be exactly 1.'
         stop
      endif
      if (vp_in < 50. .and. vs_in < 50. .and. rho_in < 50. .and. &
          vpi_in < 50. .and. vsi_in < 50. .and. rhoi_in < 50.) then
         write(0,'(a)') &
            'CIJ_tandon_and_weng: input parameters must be in m/s and kg/m^3)'
         stop
      endif
!  Theory breaks down when matrix and inclusions are the same, so return
      if (vp_in == vpi_in .and. vs_in == vsi_in .and. rho_in == rhoi_in) then
         write(0,'(2a)') 'CIJ_tandon_and_weng: warning: theory not valid for identical ', &
                     'matrix and inclusion properties.  Returning matrix properties.'
         rh_out = rho_in
         C_out = CIJ_iso(vp_in,vs_in)
         return
      endif
      
!  Initialise the elastic constant tensor
     CC = 0.
!  weighted average density
     rh = (1.0-c_in)*rho_in + c_in*rhoi_in
      rh_out = rh

     amu  = vs_in * vs_in * rho_in
     amui = vsi_in * vsi_in * rhoi_in
     alam = vp_in * vp_in * rho_in - 2.0*amu
     alami = vpi_in * vpi_in * rhoi_in - 2.0*amui
     bmi = alami + amui*2.0/3.0
     bmps = alam + amu
!  Young's modulus for matrix
     E0 = amu*(3.0*alam + 2.0*amu)/(alam + amu)
!  Poisson's ratio of the matrix.
     anu = alam/(2.0*(alam + amu))

!  Some time saving terms
     t1 = del_in**2 - 1.0
     t2 = 1.0 - anu
     t3 = 1.0 - 2.0*anu
     t4 = 3.0 * del_in*del_in
     t5 = 1.0 - del_in*del_in

! D1, D2 and D3 from Tandon and Weng (1984) (just before equation (18)).
     D1 = 1.0 + 2.0*(amui - amu)/(alami - alam)
     D2 = (alam + 2.0*amu)/(alami - alam)
     D3 = alam/(alami-alam)

! g and g' terms (appendix of Tandon and Weng 1984). g is for prolate spheroidal
! inclusions (del>1), whilst g' is for disc-like (oblate) inclusions (del<1).
!
      if (del_in >= 1.0) then
         acshdel = log(del_in + sqrt(t1)) ;
         g = (del_in*sqrt(t1) - acshdel)*del_in/sqrt(t1**3) ;
      else
!      g' below
         g = (acos(del_in) - del_in*sqrt(t5))*del_in/sqrt(t5**3) ;
      endif

! Eshelby's Sijkl tensor (appendix of Tandon and Weng 1984).
     s11 = (t3 + (t4-1.0)/t1 - (t3 + t4/t1)*g)/(2.0*t2)              
     s22 = (t4/(t1*2.0) + (t3 - 9.0/(4.0*t1))*g)/(4.0*t2)            
     s33 = s22                                                       
     s23 = (del_in**2/(2.0*t1) - (t3 + 3.0/(4.0*t1))*g)/(4.0*t2)       
     s32 = s23                                                       
     s21 = (-2.0*del_in*del_in/t1 + (t4/t1 - t3)*g)/(4.0*t2)               
     s31 = s21                                                       
     s12 = (-1.0*(t3 + 1.0/t1) + (t3 + 3.0/(2.0*t1))*g)/(2.0*t2)     
     s13 = s12                                                       
     s44 = (del_in*del_in/(2.0*t1) + (t3 - 3.0/(4.0*t1))*g)/(4.0*t2)       
     s66 = (t3 - (t1+2.0)/t1 - (t3 - 3.0*(t1+2.0)/t1)*g/2.0)/(4.0*t2)
     s55 = s66                                                       
     
! Tandon and Weng's B terms (after equation 17).
     B1 = c_in*D1 + D2 + (1.0-c_in)*(D1*s11 + 2.0*s21)    
     B2 = c_in + D3 + (1.0-c_in)*(D1*s12 + s22 + s23)     
     B3 = c_in + D3 + (1.0-c_in)*(s11 + (1.0+D1)*s21)     
     B4 = c_in*D1 + D2 + (1.0-c_in)*(s12 + D1*s22 + s23)  
     B5 = c_in + D3 + (1.0-c_in)*(s12 + s22 + D1*s23)     
     
! Tandon and Weng's A terms (after equation 20).
     A1 = D1*(B4 + B5) - 2.0*B2    
     A2 = (1.0 + D1)*B2 - (B4 + B5)
     A3 = B1 - D1*B3               
     A4 = (1.0 + D1)*B1 - 2.0*B3   
     A5 = (1.0 - D1)/(B4 - B5)     
     A = 2.0*B2*B3 - B1*(B4+B5)    
     
! Tandon and Weng (1984) equations (25) (28) (31) (32) 
     E11 = E0 /(1.0+c_in*(A1+2.0*anu*A2)/A)
     E22 = E0 &
         /(1.0+c_in*(-2.0*anu*A3 + (1.0-anu)*A4 + (1.0+anu)*A5*A)/(2.0*A))
     amu12 = amu*(1.0 + c_in/(amu/(amui-amu) + 2.0*(1.0-c_in)*s66))
     amu23 = amu*(1.0 + c_in/(amu/(amui-amu) + 2.0*(1.0-c_in)*s44))
     
! Sayers equation (36)
     anu31 = anu - c_in*(anu*(A1+2.0*anu*A2)+(A3-anu*A4)) &
                /(A + c_in*(A1+2.0*anu*A2))
     
! T&W equation (36)
!     aK12 term; bmps=plane strain bulk modulus
     anum = (1.0+anu)*(1.0-2.0*anu)
     denom = 1.0 - anu*(1.0+2.0*anu31) &
      + c_in*(2.0*(anu31-anu)*A3 + (1.0-anu*(1.0+2.0*anu31))*A4)/A
     aK23 = bmps*anum/denom
     anu12tst = E11/E22 - (1.0/amu23 + 1.0/aK23)*E11/4.0
     
! Cij - Sayers' (1992) equations (24)-(29).
! Conversion 
     CC(2,2) = amu23 + aK23                
     CC(3,3) = CC(2,2)                     
     CC(1,1) = E11 + 4.0*anu12tst*aK23     
     CC(2,3) = -amu23 + aK23               
     CC(1,2) = 2.0*anu31*aK23              
     CC(1,3) = CC(1,2)                     
     CC(5,5) = amu12                       
     CC(6,6) = CC(5,5)                     
     CC(4,4) = (CC(2,2)-CC(2,3))/2.0       
     
! Fill out matrix by symmetry
      do i=1,6
        do j=i,6
          CC(j,i) = CC(i,j)
        enddo
     enddo
     
! apply density normalisation
     C_out = CC / rh
     
     return

   end subroutine CIJ_tandon_and_weng
!------------------------------------------------------------------------------

!==============================================================================
   function Cij2cijkl(C)
!==============================================================================
!  Convert 6x6 Cij matrix to 3x3x3x3 Cijkl tensor
!  Lifted from J. Wookey's MATLAB codde cij2cijkl.
!  2005/07/04 - fixed Vera Schulte-Pelkum's bug
   
      implicit none
      real(rs),intent(in)  :: C(6,6)
      real(rs)             :: Cij2cijkl(3,3,3,3)
      real(rs)             :: CC(3,3,3,3)
      
      CC = 0.

     CC(1,1,1,1) = C(1,1)         ; CC(2,2,2,2) = C(2,2)       
     CC(3,3,3,3) = C(3,3)         ; CC(2,3,2,3) = C(4,4)       
     CC(3,2,3,2) = CC(2,3,2,3)    ; CC(2,3,3,2) = CC(2,3,2,3)  
     CC(3,2,2,3) = CC(2,3,2,3)    ; CC(1,3,1,3) = C(5,5)       
     CC(3,1,1,3) = CC(1,3,1,3)    ; CC(1,3,3,1) = CC(1,3,1,3)  
     CC(3,1,3,1) = CC(1,3,1,3)    ; CC(1,1,2,2) = C(1,2)       
     CC(2,2,1,1) = CC(1,1,2,2)    ; CC(1,1,3,3) = C(1,3)       
     CC(3,3,1,1) = CC(1,1,3,3)    ; CC(1,1,2,3) = C(1,4)       
     CC(1,1,3,2) = CC(1,1,2,3)    ; CC(2,3,1,1) = CC(1,1,2,3)  
     CC(3,2,1,1) = CC(1,1,2,3)    ; CC(1,1,1,3) = C(1,5)       
     CC(1,1,3,1) = CC(1,1,1,3)    ; CC(1,3,1,1) = CC(1,1,1,3)  
     CC(3,1,1,1) = CC(1,1,1,3)    ; CC(1,1,1,2) = C(1,6)       
     CC(1,1,2,1) = CC(1,1,1,2)    ; CC(1,2,1,1) = CC(1,1,1,2)  
     CC(2,1,1,1) = CC(1,1,1,2)    ; CC(2,2,3,3) = C(2,3)       
     CC(3,3,2,2) = CC(2,2,3,3)    ; CC(2,2,2,3) = C(2,4)       
     CC(2,2,3,2) = CC(2,2,2,3)    ; CC(2,3,2,2) = CC(2,2,2,3)  
     CC(3,2,2,2) = CC(2,2,2,3)    ; CC(2,2,1,3) = C(2,5)       
     CC(2,2,3,1) = CC(2,2,1,3)    ; CC(1,3,2,2) = CC(2,2,1,3)  
     CC(3,1,2,2) = CC(2,2,1,3)    ; CC(2,2,1,2) = C(2,6)       
     CC(2,2,2,1) = CC(2,2,1,2)    ; CC(1,2,2,2) = CC(2,2,1,2)  
     CC(2,1,2,2) = CC(2,2,1,2)    ; CC(3,3,2,3) = C(3,4)       
     CC(3,3,3,2) = CC(3,3,2,3)    ; CC(2,3,3,3) = CC(3,3,2,3)  
     CC(3,2,3,3) = CC(3,3,2,3)    ; CC(3,3,1,3) = C(3,5)       
     CC(3,3,3,1) = CC(3,3,1,3)    ; CC(1,3,3,3) = CC(3,3,1,3)  
     CC(3,1,3,3) = CC(3,3,1,3)    ; CC(3,3,1,2) = C(3,6)       
     CC(3,3,2,1) = CC(3,3,1,2)    ; CC(1,2,3,3) = CC(3,3,1,2)  
     CC(2,1,3,3) = CC(3,3,1,2)    ; CC(2,3,1,3) = C(4,5)       
     CC(3,2,1,3) = CC(2,3,1,3)    ; CC(1,3,3,2) = CC(2,3,1,3)  
     CC(1,3,2,3) = CC(2,3,1,3)    ; CC(2,3,3,1) = CC(2,3,1,3)  
     CC(3,2,3,1) = CC(2,3,1,3)    ; CC(3,1,2,3) = CC(2,3,1,3)  
     CC(3,1,3,2) = CC(2,3,1,3)    ; CC(2,3,1,2) = C(4,6)       
     CC(3,2,1,2) = CC(2,3,1,2)    ; CC(1,2,2,3) = CC(2,3,1,2)  
     CC(1,2,3,2) = CC(2,3,1,2)    ; CC(2,3,2,1) = CC(2,3,1,2)  
     CC(3,2,2,1) = CC(2,3,1,2)    ; CC(2,1,2,3) = CC(2,3,1,2)  
     CC(2,1,3,2) = CC(2,3,1,2)    ; CC(1,3,1,2) = C(5,6)       
     CC(3,1,1,2) = CC(1,3,1,2)    ; CC(1,2,1,3) = CC(1,3,1,2)  
     CC(1,2,3,1) = CC(1,3,1,2)    ; CC(1,3,2,1) = CC(1,3,1,2)  
     CC(3,1,2,1) = CC(1,3,1,2)    ; CC(2,1,1,3) = CC(1,3,1,2)  
     CC(2,1,3,1) = CC(1,3,1,2)    ; CC(1,2,1,2) = C(6,6)       
     CC(2,1,1,2) = CC(1,2,1,2)    ; CC(1,2,2,1) = CC(1,2,1,2)  
     CC(2,1,2,1) = CC(1,2,1,2)  
      
      Cij2cijkl = CC
      
      return
   end function Cij2cijkl
!------------------------------------------------------------------------------

!==============================================================================
   function cijkl2Cij(CC)
!==============================================================================
!  Convert a 3x3x3x3 elasticity tensor to a 6x6 tensor
!  Lifted from cijkl2cij, MATLAB code by J. Wookey.
   
     implicit none
     real(rs),intent(in)  :: CC(3,3,3,3)
     real(rs)             :: cijkl2Cij(6,6)
     real(rs)             :: C(6,6)
     integer              :: im,jm,km,lm,iv,jv
     
     C = 0.
     do im=1,3
       do jm=1,3
         do km=1,3
            do lm=1,3
              if ( CC(im,jm,km,lm) /= 0.0) then
                call ijkl2ij_local(im,jm,km,lm,iv,jv)
                C(iv,jv) = CC(im,jm,km,lm);
              endif
            enddo
         enddo
       enddo
     enddo
   
     cijkl2cij = C
     
     return
   
!  Declare internal utility function
   CONTAINS
   
      subroutine ijkl2ij_local(ii,jj,kk,ll,iv,jv)
       implicit none
       integer, intent(in) :: ii,jj,kk,ll
       integer,intent(out) :: iv,jv
       
       if (ii==1 .and. jj==1) iv=1
       if (ii==1 .and. jj==2) iv=6
       if (ii==1 .and. jj==3) iv=5
       if (ii==2 .and. jj==1) iv=6
       if (ii==2 .and. jj==2) iv=2
       if (ii==2 .and. jj==3) iv=4
       if (ii==3 .and. jj==1) iv=5
       if (ii==3 .and. jj==2) iv=4
       if (ii==3 .and. jj==3) iv=3
       if (kk==1 .and. ll==1) jv=1
       if (kk==1 .and. ll==2) jv=6
       if (kk==1 .and. ll==3) jv=5
       if (kk==2 .and. ll==1) jv=6
       if (kk==2 .and. ll==2) jv=2
       if (kk==2 .and. ll==3) jv=4
       if (kk==3 .and. ll==1) jv=5
       if (kk==3 .and. ll==2) jv=4
       if (kk==3 .and. ll==3) jv=3
       
       return
      end subroutine ijkl2ij_local 
   
   end function cijkl2Cij
!------------------------------------------------------------------------------

!==============================================================================
   function CIJ_Au(C_in)
!==============================================================================
!  Compute the Universal Anisotropy Index for a set of elastic constants
!  See: Ranganathan and Ostoja-Starzewski. Universal elastic anisotropy index. 
!      Phys. Rev. Lett. (2008) vol. 101 (5) pp. 055504
!  and: Hill, R. The elastic behaviour of a crystalline aggregate. 
!      P Phys Soc Lond A (1952) vol. 65 (389) pp. 349-355
   
     implicit none
     
     real(rs),intent(in) :: C_in(6,6)
     real(rs)            :: CIJ_Au
     real(rs)            :: C(6,6),S(6,6),Kv,Kr,Gv,Gr
     
   !  Get input
     C = C_in
     
   !  Find stiffness from inverse
     call inverse(6,6,C,S)
     
   !  Calculate Voigt moduli
     Kv = (1._rs/9._rs) * (C(1,1) + C(2,2) + C(3,3) + 2._rs*(C(1,2) + C(2,3) + C(3,1)))
     
     Gv = (1._rs/15._rs) * (C(1,1) + C(2,2) + C(3,3) - (C(1,2) + C(2,3) + C(3,1)) + &
                  3._rs*(C(4,4) + C(5,5) + C(6,6)))
     
   !  Calculate Reuss moduli
     Kr = 1._rs/(S(1,1) + S(2,2) + S(3,3) + 2._rs*(S(1,2) + S(2,3) + S(3,1)))
     
     Gr = 15._rs/(4._rs*(S(1,1) + S(2,2) + S(3,3)) - 4._rs*(S(1,2) + S(2,3) + S(3,1)) + &
            3._rs*(S(4,4) + S(5,5) + S(6,6)))
     
   !  Calculate Au
     CIJ_Au = 5._rs*(Gv/Gr) + (Kv/Kr) - 6._rs
      
      return
   end function CIJ_Au
!------------------------------------------------------------------------------

!===============================================================================
   subroutine CIJ_brow_chev(Cin,CI,CX,CT,CO,CM,CR) !,pI,pX,pT,pO,pM,pR)
!===============================================================================
!  Returns parts of the input elasticity tensor, decomposed a la Browaeys and 
!  Chevrot, GJI, 2004
!  Input is 6x6 Voigt Cij matrix
!  Output is a selection of one or more the decomposed matrices:
!     CI = isotropic part,    pS is proportion of tensor described by CS
!     CX = hexagonal part,    pX  "    "        "   "        "      " CX
!     CT = tetragonal part,   pT  "    "        "   "        "      " CT
!     CO = orthorhombic part, pO  "    "        "   "        "      " CO
!     CM = monoclinic part,   pM  "    "        "   "        "      " CM
!     CR = triclinic part,    pR  "    "        "   "        "      " CR
!-------------------------------------------------------------------------------
!  2011/08: values of pI, pX, etc., do not seem to be correct at the moment...
!           This needs to be fixed.  Is this because pI == pi???
      implicit none
      
      real(rs),intent(in)  :: Cin(6,6)
      real(rs),intent(out),dimension(6,6),optional :: CI,CX,CT,CO,CM,CR
!      real(rs),intent(out),optional :: pI,pX,pT,pO,pM,pR
      real(rs) :: M(21,21)    ! Projector
      real(rs) :: C(6,6)
      real(rs) :: X(21),XH(21),Xin(21),CH(6,6)
      integer  :: i,j
      
!  Input matrix and vector
      C = Cin
      Xin = CIJ2X(C)

!  Isotropic part
      X = CIJ2X(C)
      M = 0._rs
      M(1,1:9) = (/ 3._rs/15._rs,       3._rs/15._rs,        3._rs/15._rs,       &
                  sqrt(2._rs)/15._rs,   sqrt(2._rs)/15._rs,  sqrt(2._rs)/15._rs, &
                  2._rs/15._rs,         2._rs/15._rs,        2._rs/15._rs        /)
      M(2,:) = M(1,:)
      M(3,:) = M(1,:)
      M(4,1:9) = (/ sqrt(2._rs)/15._rs, sqrt(2._rs)/15._rs,  sqrt(2._rs)/15._rs, &
                  4._rs/15._rs,         4._rs/15._rs,        4._rs/15._rs,       &
                  -sqrt(2._rs)/15._rs,  -sqrt(2._rs)/15._rs, -sqrt(2._rs)/15._rs /)
      M(5,:) = M(4,:)
      M(6,:) = M(4,:)
      M(7,1:9) = (/ 2._rs/15._rs,       2._rs/15._rs,        2._rs/15._rs,       &
                  -sqrt(2._rs)/15._rs,  -sqrt(2._rs)/15._rs, -sqrt(2._rs)/15._rs,&
                  1._rs/5._rs,          1._rs/5._rs,         1._rs/5._rs         /)
      M(8,:) = M(7,:)
      M(9,:) = M(7,:)
      
      XH = matmul(M,X)
      CH = X2CIJ(XH)
      if (present(CI)) CI = CH
!      if (present(pI)) pI = sum(XH**2)/sum(Xin**2)
      C = C - CH
      
!  Hexagonal part
      X = CIJ2X(C)
      M = 0._rs
      M(1,1:9) = (/ 3._rs/8._rs,             3._rs/8._rs,  &
                  0._rs,         0._rs,      0._rs,        &
                  1._rs/(4._rs*sqrt(2._rs)), 0._rs, 0._rs, 1._rs/4._rs /)
      M(2,:) = M(1,:)
      M(3,3) = 1._rs
      M(4,4) = 1._rs/2._rs    ;  M(4,5) = 1._rs/2._rs
      M(5,:) = M(4,:)
      M(6,1:9) = (/ 1._rs/(4._rs*sqrt(2._rs)), 1._rs/(4._rs*sqrt(2._rs)), &
                  0._rs, 0._rs, 0._rs, 3._rs/4._rs, 0._rs, 0._rs, -1._rs/(2._rs*sqrt(2._rs)) /)
      M(7,7) = 1._rs/2._rs    ;  M(7,8) = 1._rs/2._rs
      M(8,:) = M(7,:)
      M(9,1:9) = (/ 1._rs/4._rs, 1._rs/4._rs, 0._rs, 0._rs, 0._rs, &
                    -1._rs/(2._rs*sqrt(2._rs)), 0._rs, 0._rs, 1._rs/2._rs /)
      
      XH = matmul(M,X)
      CH = X2CIJ(XH)
      if (present(CX)) CX = CH
!      if (present(pX)) pX = sum(XH**2)/sum(Xin**2)
      C = C - CH
      
!  Tetragonal part
      X = CIJ2X(C)
      M = 0._rs
      M(1,1) = 1._rs/2._rs   ;  M(1,2) = M(1,1)   ;  M(2,1) = M(1,2)
      M(2,2) = M(1,1)        ;  M(3,3) = 1._rs
      M(4,4) = M(1,1)        ;  M(4,5) = M(4,4)   ;  M(5,4) = M(4,5)
      M(5,5) = M(4,4)
      M(6,6) = 1._rs         ;  M(9,9) = 1._rs
      M(7,7) = M(1,1)   ;  M(7,8) = M(7,7)  ;  M(8,7) = M(7,8)  ;  M(8,8) = M(7,7)
      
      XH = matmul(M,X)
      CH = X2CIJ(XH)
      if (present(CT)) CT = CH
!      if (present(pT)) pT = sum(XH**2)/sum(Xin**2)
      C = C - CH
      
!  Orthorhombic part
      X = CIJ2X(C)
      M = 0._rs
      do i=1,9; M(i,i) = 1._rs; enddo
      
      XH = matmul(M,X)
      CH = X2CIJ(XH)
      if (present(CO)) CO = CH
!      if (present(pO)) pO = sum(XH**2)/sum(Xin**2)
      C = C - CH
      
!  Monoclinic part
      X = CIJ2X(C)
      M = 0._rs
      do i=1,21; M(i,i) = 1._rs; enddo
      M(10,10) = 0._rs  ;  M(11,11) = 0._rs  ;  M(13,13) = 0._rs  ;  M(14,14) = 0._rs
      M(16,16) = 0._rs  ;  M(17,17) = 0._rs  ;  M(19,19) = 0._rs  ;  M(20,20) = 0._rs
      
      XH = matmul(M,X)
      CH = X2CIJ(XH)
      if (present(CM)) CM = CH
!      if (present(pM)) pM = sum(XH**2)/sum(Xin**2)
      C = C - CH
      
!  Triclinc part(?)
      if (present(CR)) then
         write(0,'(a)') 'anisotropy_ajn: CIJ_brow_chev: WARNING: triclinic part not verified.'
         CR = C
      endif
!      if (present(PR)) then
!         write(0,'(a)') 'anisotropy_ajn: CIJ_brow_chev: WARNING: triclinic part not verified.'
!         XH = CIJ2X(C)
!         pR = sum(XH**2)/sum(Xin**2)
!      endif
         
      return
   end subroutine CIJ_brow_chev
!-------------------------------------------------------------------------------               

!===============================================================================
   function CIJ2X(C)
!===============================================================================
!  Returns the elastic vector, as defined by Browaeys & Chevrot, GJI, 2004
      implicit none
      real(rs),intent(in) :: C(6,6)
      real(rs)            :: CIJ2X(21)
      
      CIJ2X(1)  = C(1,1)
      CIJ2X(2)  = C(2,2)
      CIJ2X(3)  = C(3,3)
      CIJ2X(4)  = sqrt(2._rs)*C(2,3)
      CIJ2X(5)  = sqrt(2._rs)*C(1,3)
      CIJ2X(6)  = sqrt(2._rs)*C(1,2)
      CIJ2X(7)  = 2._rs*C(4,4)
      CIJ2X(8)  = 2._rs*C(5,5)
      CIJ2X(9)  = 2._rs*C(6,6)
      CIJ2X(10) = 2._rs*C(1,4)
      CIJ2X(11) = 2._rs*C(2,5)
      CIJ2X(12) = 2._rs*C(3,6)
      CIJ2X(13) = 2._rs*C(3,4)
      CIJ2X(14) = 2._rs*C(1,5)
      CIJ2X(15) = 2._rs*C(2,6)
      CIJ2X(16) = 2._rs*C(2,4)
      CIJ2X(17) = 2._rs*C(3,5)
      CIJ2X(18) = 2._rs*C(1,6)
      CIJ2X(19) = 2._rs*sqrt(2._rs)*C(5,6)
      CIJ2X(20) = 2._rs*sqrt(2._rs)*C(4,6)
      CIJ2X(21) = 2._rs*sqrt(2._rs)*C(4,5)
      
      return
   end function CIJ2X
!-------------------------------------------------------------------------------

!===============================================================================
   function X2CIJ(X)
!===============================================================================
!  Return the 6x6 Voigt elasticity matrix, given the elastic vector as defined by
!  Browaeys & Chevrot, GJI, 2004
      implicit none
      real(rs), intent(in) :: X(21)
      real(rs)             :: X2CIJ(6,6)
      integer :: i,j
      
      X2CIJ(1,1) = X(1)
      X2CIJ(2,2) = X(2)
      X2CIJ(3,3) = X(3)
      X2CIJ(2,3) = (1._rs/sqrt(2._rs))*X(4)
      X2CIJ(1,3) = (1._rs/sqrt(2._rs))*X(5)
      X2CIJ(1,2) = (1._rs/sqrt(2._rs))*X(6)
      X2CIJ(4,4) = (1._rs/2._rs)*X(7)
      X2CIJ(5,5) = (1._rs/2._rs)*X(8)
      X2CIJ(6,6) = (1._rs/2._rs)*X(9)
      X2CIJ(1,4) = (1._rs/2._rs)*X(10)
      X2CIJ(2,5) = (1._rs/2._rs)*X(11)
      X2CIJ(3,6) = (1._rs/2._rs)*X(12)
      X2CIJ(3,4) = (1._rs/2._rs)*X(13)
      X2CIJ(1,5) = (1._rs/2._rs)*X(14)
      X2CIJ(2,6) = (1._rs/2._rs)*X(15)
      X2CIJ(2,4) = (1._rs/2._rs)*X(16)
      X2CIJ(3,5) = (1._rs/2._rs)*X(17)
      X2CIJ(1,6) = (1._rs/2._rs)*X(18)
      X2CIJ(5,6) = (1._rs/(2._rs*sqrt(2._rs)))*X(19)
      X2CIJ(4,6) = (1._rs/(2._rs*sqrt(2._rs)))*X(20)
      X2CIJ(4,5) = (1._rs/(2._rs*sqrt(2._rs)))*X(21)
      
      do i=1,6
         do j=i,6
            X2CIJ(j,i) = X2CIJ(i,j)
         enddo
      enddo
      
      return
   end function X2CIJ
!-------------------------------------------------------------------------------

!===============================================================================
   subroutine CIJ_isotropic_average(C,r,Ciso,Vp,Vs)
!===============================================================================
      implicit none
      
      real(rs), intent(in) :: C(6,6), r
      real(rs), intent(out), optional :: Ciso(6,6), Vp, Vs
      
      write(0,'(a)') 'anisotropy_ajn: CIJ_isotropic_average is not working yet.'
      stop
      
   end subroutine CIJ_isotropic_average
!-------------------------------------------------------------------------------

!==============================================================================
   subroutine inverse(n, sz, A, AI)
! inverse.f90  compute AI = A^-1  modified simeq.f90
     implicit none
     integer, intent(in) :: n  ! number of equations
     integer, intent(in) :: sz ! dimension of arrays
     real(rs), dimension(sz,sz), intent(in) :: A
     real(rs), dimension(sz,sz), intent(inout) :: AI
   
!      PURPOSE : COMPUTE INVERSE WITH REAL COEFFICIENTS  |AI| = |A|^-1
!                                                                   
!      INPUT  : THE NUMBER OF ROWS  n
!               THE DIMENSION OF A, sz
!               THE REAL MATRIX  A
!      OUTPUT : THE REAL MATRIX  AI                                  

    integer, dimension(n) :: ROW             ! ROW INTERCHANGE INDICIES 
    integer, dimension(n) :: COL             ! COL INTERCHANGE INDICIES 
    double precision, dimension(n) :: TEMP   ! INTERCHANGE VECTOR
    integer :: HOLD , I_PIVOT, J_PIVOT       ! PIVOT INDICIES 
    double precision :: PIVOT                ! PIVOT ELEMENT VALUE 
    double precision :: ABS_PIVOT, NORM1
    integer :: i, j, k
   
    NORM1 = 0.0D0;
    ! BUILD WORKING DATA STRUCTURE 
    do i=1,n
      do j=1,n
       AI(i,j) = A(i,j)
       if( abs(AI(i,j)) > NORM1 ) then
         NORM1 = abs(AI(i,j))
       end if
      end do ! j
    end do ! i
    ! SET UP ROW AND COL  INTERCHANGE VECTORS 
    do k=1,n
      ROW(k) = k
      COL(k) = k
    end do ! k
   
    ! BEGIN MAIN REDUCTION LOOP 
    do k=1,n
      ! FIND LARGEST ELEMENT FOR PIVOT 
      PIVOT = AI(ROW(k), COL(k))
      I_PIVOT = k
      J_PIVOT = k
      do i=k,n
       do j=k,n
         ABS_PIVOT = abs(PIVOT)
         if( abs(AI(ROW(i), COL(j))) > ABS_PIVOT ) then
          I_PIVOT = i
          J_PIVOT = j
          PIVOT = AI(ROW(i), COL(j))
         end if
       end do ! j
      end do ! i
      ABS_PIVOT = abs(PIVOT)
   
      ! HAVE PIVOT, INTERCHANGE ROW, COL POINTERS 
      HOLD = ROW(k)
      ROW(k) = ROW(I_PIVOT)
      ROW(I_PIVOT) = HOLD
      HOLD = COL(k)
      COL(k) = COL(J_PIVOT)
      COL(J_PIVOT) = HOLD
   
      ! CHECK FOR NEAR SINGULAR 
      if( ABS_PIVOT < 1.0D-52*NORM1 ) then
       do j=1,n
         AI(ROW(k),j) = 0.0D0
       end do ! j
       do i=1,n
         AI(i,COL(k)) = 0.0D0
       end do ! i
       print *, 'redundant row (singular) ', ROW(k)
      else
       !                            REDUCE ABOUT PIVOT
       AI(ROW(k), COL(k)) = 1.0 / PIVOT
       do j=1,n
         if( j .ne. k ) then
          AI(ROW(k), COL(j)) = AI(ROW(k), COL(j)) * AI(ROW(k), COL(k))
         end if
       end do ! j
       !                            INNER REDUCTION LOOP
       do i=1,n
         if( k .ne. i ) then
          do j=1,n
            if( k .ne. j ) then
             AI(ROW(i), COL(j)) = AI(ROW(i), COL(j)) - &
                             AI(ROW(i), COL(k)) * AI(ROW(k), COL(j))
            end if
          end do ! j
          AI(ROW(i), COL(k)) = - AI(ROW(i), COL(k)) * AI(ROW(k), COL(k))
         end if
       end do ! i
      end if
      ! FINISHED INNER REDUCTION 
    end do ! k
    ! END OF MAIN REDUCTION LOOP 
   
    !                              UNSCRAMBLE ROWS
    do j=1,n
      do i=1,n
       TEMP(COL(i)) = AI(ROW(i), j)
      end do ! i
      do i=1,n
       AI(i,j)= TEMP(i)
      end do !i
    end do ! j
    !                              UNSCRAMBLE COLUMNS
    do i=1,n
      do j=1,n
       TEMP(ROW(j)) = AI(i,COL(j))
      end do ! j
      do j=1,n
       AI(i,j)= TEMP(j)
      end do ! j
    end do ! i
   end subroutine inverse 
!-------------------------------------------------------------------------------


   end module anisotropy_ajn
!=======================================================================================
