
program test_materials
  use mod_conductor
  use mod_superconductor
  use mod_ferromagnet
  use mod_multilayer
  use mod_dos
  integer              :: n
  real(dp)             :: erg(600)
  type(conductor)      :: m
  type(superconductor) :: s
  type(ferromagnet)    :: f

  call energy_range(erg, coupling = 0.2_dp)

  f = ferromagnet(erg, [0.0_dp, 0.0_dp, 0.0_dp], spinorbit = [pauli1, pauli2, pauli3])
  s = superconductor(erg, coupling = 0.2_dp, spinorbit = [pauli1, pauli2, pauli3])
  m = conductor(erg, spinorbit = [pauli1, pauli2, pauli3])

  !call f%spinorbit(1)%print
  !call f%spinorbit(2)%print
  !call f%spinorbit(3)%print
  !call s%spinorbit(1)%print
  !call s%spinorbit(2)%print
  !call s%spinorbit(3)%print
  !call m%spinorbit(1)%print
  !call m%spinorbit(2)%print
  !call m%spinorbit(3)%print

  call connect(f, s, 0.20_dp, 0.20_dp)
  !call connect(s, m, 0.20_dp, 0.20_dp)
  !call connect(m, f, 0.3_dp, 0.3_dp)

  !open(unit=1, file='test_materials.dat')
  !call calculate_dos(s, iterations=2, unit=1)
  !close(unit=1)
 

  !do n=1,size(f%location)
  !  f%exchange(1,n) = 0.1_dp*sin(1.57*f%location(n))
  !  f%exchange(2,n) = 0.1_dp*cos(1.57*f%location(n))
  !  f%exchange(3,n) = 0.1_dp
  !end do

  ! Scalar and array exchange

  open(unit=1, file='test_materials.dat')
  call f%write_dos(1, 0.0_dp, 1.0_dp)
  call s%write_dos(1, 1.0_dp, 2.0_dp)
  call m%write_dos(1, 2.0_dp, 3.0_dp)
  close(unit=1)

  !call s%internals_update
  do n=1,128
    print *,s%get_gap(s%location(n))
  end do

  !do n=1,3
    call f%update
    !call s%update
    !call m%update
    !call s%update
    !call f%update
  !end do

  do n=1,128
    print *,s%get_gap(s%location(n))
  end do

  open(unit=1, file='test_materials.dat')
  call f%write_dos(1, 0.0_dp, 1.0_dp)
  call s%write_dos(1, 1.0_dp, 2.0_dp)
  call m%write_dos(1, 2.0_dp, 3.0_dp)
  close(unit=1)


  !call b%update
  !print *,b%state(50,64)%get_dos()
  !call c%update
  !print *,c%state(50,64)%get_dos()
  !call b%update
  !print *,b%state(50,64)%get_dos()
  !call a%update
  !print *,a%state(50,64)%get_dos()
  !call b%update
  !print *,b%state(50,64)%get_dos()

  !print *, metal%state(50,64)%get_dos()

  !system = [ metal, metal, metal ]

  !subroutine write_test(fd)
  !end subroutine
end program
