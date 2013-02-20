program test_inout
!===============================================================================
!  Tests an algorithm for finding out whether we're inside a polygon or not.

   use spherical_geometry
   
   integer,parameter :: n=56
   real(8) :: x(n), y(n), px, py, s, a0, a1
   real(8) :: xt(n),yt(n)
   real(8),parameter :: tol = 1._8
   logical :: inside
   
! Plate AP   
x(1) = -15.736; y(1) = -75.916
x(2) = -16.330; y(2) = -75.292
x(3) = -16.823; y(3) = -74.609
x(4) = -17.373; y(4) = -73.949
x(5) = -17.747; y(5) = -73.400
x(6) = -18.257; y(6) = -72.737
x(7) = -18.721; y(7) = -72.266
x(8) = -19.298; y(8) = -71.746
x(9) = -19.811; y(9) = -71.487
x(10) = -20.249; y(10) = -71.362
x(11) = -20.758; y(11) = -71.323
x(12) = -21.262; y(12) = -71.249
x(13) = -21.965; y(13) = -71.307
x(14) = -21.965; y(14) = -71.307
x(15) = -21.734; y(15) = -70.683
x(16) = -21.500; y(16) = -70.062
x(17) = -21.500; y(17) = -69.114
x(18) = -21.500; y(18) = -68.166
x(19) = -21.500; y(19) = -67.655
x(20) = -21.500; y(20) = -67.144
x(21) = -21.500; y(21) = -66.634
x(22) = -21.500; y(22) = -66.123
x(23) = -21.465; y(23) = -65.427
x(24) = -21.427; y(24) = -64.732
x(25) = -21.399; y(25) = -64.139
x(26) = -21.368; y(26) = -63.545
x(27) = -20.759; y(27) = -63.360
x(28) = -20.150; y(28) = -63.176
x(29) = -19.511; y(29) = -63.286
x(30) = -18.872; y(30) = -63.396
x(31) = -18.375; y(31) = -63.617
x(32) = -17.878; y(32) = -63.836
x(33) = -17.464; y(33) = -63.856
x(34) = -17.402; y(34) = -64.585
x(35) = -17.110; y(35) = -65.419
x(36) = -16.729; y(36) = -65.795
x(37) = -16.348; y(37) = -66.171
x(38) = -15.714; y(38) = -66.696
x(39) = -15.079; y(39) = -67.218
x(40) = -14.527; y(40) = -67.423
x(41) = -14.028; y(41) = -68.008
x(42) = -13.527; y(42) = -68.590
x(43) = -13.395; y(43) = -69.046
x(44) = -13.261; y(44) = -69.501
x(45) = -13.035; y(45) = -70.125
x(46) = -12.807; y(46) = -70.747
x(47) = -12.578; y(47) = -71.392
x(48) = -12.348; y(48) = -72.036
x(49) = -12.418; y(49) = -72.655
x(50) = -12.486; y(50) = -73.274
x(51) = -13.182; y(51) = -73.850
x(52) = -13.876; y(52) = -74.429
x(53) = -14.497; y(53) = -74.922
x(54) = -15.117; y(54) = -75.418
x(55) = -15.736; y(55) = -75.916
x(56) = -15.736; y(56) = -75.916

!  Try it with the points swapped round
!do i=1,n
!   xt(i) = x(n-i+1)
!   yt(i) = y(n-i+1)
!enddo
!x = xt
!y = yt

!  Trial point INSIDE
   px = -18.9151
   py = -72.0074
   
   px = -17.
   py = -70.
   
   inside = sph_poly_inout(px,py,x,y,degrees=.true.)
   write(*,*) inside
   
!  Trial point OUTSIDE
   px = -18.9814
   py = -72.1444
   inside = sph_poly_inout(px,py,x,y,degrees=.true.)
   write(*,*) inside
   
end program test_inout
   