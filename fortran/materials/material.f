! This module defines the data type 'material',  which models the state of a physical material for a discretized range of
! positions and energies. This is an abstract type, meaning that it is not intended to be instantiated on its own, but is
! intended as a base type for physical materials like conductors, superconductors, and ferromagnets. In other words, this
! type defines the essential data structures and program structure, while the derived subtypes will define actual physics.
!
! Author:  Jabir Ali Ouassou <jabirali@switzerlandmail.ch>
! Created: 2015-07-29
! Updated: 2015-08-14

module mod_material
  use mod_green
  implicit none

  ! Type declarations
  type, abstract :: material
    ! These parameters determine the basic physical behaviour of a diffusive material
    real(dp)                                  :: thouless        =  1.00_dp               ! Thouless energy of the material (ratio of the diffusion constant to the squared material length)
    real(dp)                                  :: scattering      =  0.01_dp               ! Imaginary energy term (this models inelastic scattering processes and stabilizes the BVP solver)

    ! The physical state of the material is modeled as a discretized range of energies, positions, and quasiclassical Green's functions
    real(dp),                     allocatable :: energy(:)                                ! Discretized domain for the energies
    real(dp),                     allocatable :: location(:)                              ! Discretized domain for the positions
    type(green),                  allocatable :: greenr(:,:)                              ! Discretized values for the Green's function (retarded component)

    ! Hybrid structures are modeled by a double-linked material list, where these two pointers define the neighbours of the current node
    class(material),                  pointer :: material_a      => null()                ! Material connected to this one at the left  interface (default: null pointer, meaning vacuum)
    class(material),                  pointer :: material_b      => null()                ! Material connected to this one at the right interface (default: null pointer, meaning vacuum)

    ! The package bvp_solver is used to handle differential equations, and will be controlled by the following parameters
    integer                                   :: scaling         =  128                   ! Maximal allowed increase in the mesh resolution (range: 2^N, N>1)
    integer                                   :: order           =  4                     ! Order of the Runge—Kutta method used by the solver (range: 2, 4, 6)
    integer                                   :: control         =  2                     ! Error control method (1: defect, 2: global error, 3: 1 then 2, 4: 1 and 2)
    integer                                   :: information     =  0                     ! How much information that should be written to standard out (range: [-1,2])
    real(dp)                                  :: tolerance       =  1e-6_dp               ! Error tolerance (determines the maximum allowed defect or global error)
    real(dp)                                  :: difference      =  1e+6_dp               ! Maximal difference between this and the previous state (calculated from the Riccati parameters)

    ! The following variables are used for input/output purposes, and should be modified by class(material) constructors
    character(len=128)                        :: type_string     =  'MATERIAL'            ! The type string should describe the specific class(material) subtype
  contains
    ! These methods define how to update the physical state of the material
    procedure(init),                 deferred :: init                                     ! Initializes  the Green's functions
    procedure                                 :: update          => material_update       ! Recalculates the Green's functions
    procedure(update),               deferred :: update_prehook                           ! Executed before calculating the Green's functions
    procedure(update),               deferred :: update_posthook                          ! Executed after  calculating the Green's functions

    ! These methods define the physical equations used by the update methods
    procedure(diffusion_equation),   deferred :: diffusion_equation                       ! Diffusion equation that describes the material
    procedure(interface_equation_a), deferred :: interface_equation_a                     ! Boundary condition at the left  interface
    procedure(interface_equation_b), deferred :: interface_equation_b                     ! Boundary condition at the right interface

    ! These methods define miscellaneous utility functions
    procedure                                 :: save            => material_save         ! Saves the state of the conductor to a different object
    procedure                                 :: load            => material_load         ! Loads the state of the conductor from a different object
    procedure                                 :: write_dos       => material_write_dos    ! Writes the density of states to a given output unit

  end type

  ! Interface declarations
  abstract interface
    pure subroutine init(this, gap)
      ! This interface is used for the deferred procedure init.
      import material, dp

      class(material), intent(inout) :: this
      complex(dp),     intent(in   ) :: gap
    end subroutine
  end interface

  abstract interface
    impure subroutine update(this)
      ! This interface is used for the deferred procedures update_prehook and update_posthook.
      import material

      class(material), intent(inout) :: this
    end subroutine
  end interface

  abstract interface
    pure subroutine diffusion_equation(this, e, z, g, gt, dg, dgt, d2g, d2gt)
      ! This interface is used for the deferred procedure diffusion_equation.
      import material, spin, dp

      class(material), intent(in   ) :: this
      type(spin),      intent(in   ) :: g, gt, dg, dgt
      type(spin),      intent(inout) :: d2g, d2gt
      complex(dp),     intent(in   ) :: e
      real(dp),        intent(in   ) :: z
    end subroutine
  end interface

  abstract interface
    pure subroutine interface_equation_a(this, a, g, gt, dg, dgt, r, rt)
      ! This interface is used for the deferred procedure interface_equation_a.
      import material, green, spin, dp

      class(material),          intent(in   ) :: this
      type(green),              intent(in   ) :: a
      type(spin),               intent(in   ) :: g, gt, dg, dgt
      type(spin),               intent(inout) :: r, rt
    end subroutine
  end interface

  abstract interface
    pure subroutine interface_equation_b(this, b, g, gt, dg, dgt, r, rt)
      ! This interface is used for the deferred procedure interface_equation_b.
      import material, green, spin, dp

      class(material),          intent(in   ) :: this
      type(green),              intent(in   ) :: b
      type(spin),               intent(in   ) :: g, gt, dg, dgt
      type(spin),               intent(inout) :: r, rt
    end subroutine
  end interface
contains

  !--------------------------------------------------------------------------------!
  !                    IMPLEMENTATION OF STATE UPDATE METHODS                      !
  !--------------------------------------------------------------------------------!

  impure subroutine material_update(this)
    ! This subroutine updates the current estimate for the state of the material by numerically solving the diffusion equation.
    use bvp_m

    class(material), intent(inout) :: this  ! Material that will be updated
    type(green)                    :: a     ! State at this energy at the left  interface
    type(green)                    :: b     ! State at this energy at the right interface
    complex(dp)                    :: e     ! Complex energy relative to the Thouless energy
    integer                        :: n     ! Outer loop variable (current energy)

    ! Call the prehook method
    call this%update_prehook

    ! Status information
    if (this%information >= 0) then
      write(stdout,'(a)') ' :: ' // trim(this%type_string) // '                                     '
    end if

    ! Reset the difference since last update to zero
    this%difference = 0.0_dp

    ! Loop over the discretized energy levels
    do n=1,size(this%energy)
      block
        ! Declare local block variables
        real(dp)      :: u(32,size(this%location))  ! Representation of the retarded Green's functions
        real(dp)      :: d(32,size(this%location))  ! Work array used to calculate the change in u(·,·)
        type(bvp_sol) :: sol                        ! Workspace for the bvp_solver procedures
        integer       :: m                          ! Inner loop variable (current location)

        ! Status information
        if (this%information >= 0) then
          write(stdout,'(4x,a,1x,i4,1x,a,1x,i4,1x,a,f0.5,a1)',advance='no') &
            '[',n,'/',size(this%energy),']  E = ',this%energy(n), achar(13)
          flush(stdout)
        end if

        ! Convert all states at this energy level to real-valued state vectors
        do m=1,size(this%location)
          u(:,m) = this%greenr(n,m)
        end do

        ! Copy the contents of the state vector to the difference vector
        d = u

        ! Calculate the complex energy (relative to the Thouless energy)
        e = cmplx(this%energy(n)/this%thouless, this%scattering/this%thouless, kind=dp)

        ! Update the matrices used to evaluate boundary conditions
        if (associated(this%material_a)) then
          a = this%material_a%greenr(n,ubound(this%material_a%greenr,2))
        else
          a = green0
        end if

        if (associated(this%material_b)) then
          b = this%material_b%greenr(n,lbound(this%material_b%greenr,2))
        else
          b = green0
        end if

        ! Initialize bvp_solver
        sol = bvp_init(32, 16, this%location, u, max_num_subintervals=(size(this%location)*this%scaling))

        ! Solve the differential equation
        sol = bvp_solver(sol, ode, bc, method=this%order, error_control=this%control, tol=this%tolerance, trace=this%information)

        ! Use the results to update the state
        call bvp_eval(sol, this%location, u)
        do m=1,size(this%location)
          this%greenr(n,m) = u(:,m)
        end do

        ! Update the difference vector
        d = abs(u - d)

        ! Update the maximal difference since last update
        this%difference = max(this%difference,maxval(d))

        ! Clean up after bvp_solver
        call bvp_terminate(sol)
      end block
    end do

    ! Status information
    if (this%information >= 0) then
      write(stdout,'(4x,a,f10.8,a)') 'Max change: ',this%difference,'                                        '
      flush(stdout)
    end if

    ! Call the posthook method
    call this%update_posthook
  contains
    pure subroutine ode(z, u, f)
      ! Definition of the differential equation u'=f(z,u).
      real(dp), intent(in)  :: z
      real(dp), intent(in)  :: u(32)
      real(dp), intent(out) :: f(32)
      type(spin)            :: g, gt, dg, dgt, d2g, d2gt

      ! Extract the Riccati parameters
      g   = u( 1: 8)
      gt  = u( 9:16)
      dg  = u(17:24)
      dgt = u(25:32)

      ! Calculate the second-derivatives of the Riccati parameters
      call this%diffusion_equation(e, z, g, gt, dg, dgt, d2g, d2gt)
       
      ! Pack the results into a state vector
      f( 1: 8) = dg
      f( 9:16) = dgt
      f(17:24) = d2g
      f(25:32) = d2gt
    end subroutine

    pure subroutine bc(ua, ub, bca, bcb)
      ! Definition of the boundary conditions bca=g(ua) and bcb=g(ub).
      real(dp), intent(in)  :: ua(32)
      real(dp), intent(in)  :: ub(32)
      real(dp), intent(out) :: bca(16)
      real(dp), intent(out) :: bcb(16)

      type(spin)            :: g1, gt1, dg1, dgt1, r1, rt1
      type(spin)            :: g2, gt2, dg2, dgt2, r2, rt2

      ! State at the left end of the material
      g1   = ua( 1: 8)
      gt1  = ua( 9:16)
      dg1  = ua(17:24)
      dgt1 = ua(25:32)

      ! State at the right end of the material
      g2   = ub( 1: 8)
      gt2  = ub( 9:16)
      dg2  = ub(17:24)
      dgt2 = ub(25:32)

      ! Calculate residuals from the boundary conditions
      call this%interface_equation_a(a, g1, gt1, dg1, dgt1, r1, rt1)
      call this%interface_equation_b(b, g2, gt2, dg2, dgt2, r2, rt2)

      ! Pack the results into state vectors
      bca(1: 8) = r1
      bca(9:16) = rt1
      bcb(1: 8) = r2
      bcb(9:16) = rt2
    end subroutine
  end subroutine

  !--------------------------------------------------------------------------------!
  !                      IMPLEMENTATION OF UTILITY METHODS                         !
  !--------------------------------------------------------------------------------!

  pure subroutine material_save(this, backup)
    ! Exports the state of the material to a different object.
    class(material), intent(inout) :: this
    class(material), intent(inout) :: backup

    ! Make sure enough memory is allocated
    if (allocated(backup%greenr)) then
      if (ubound(this%greenr,1) /= ubound(backup%greenr,1) .or. ubound(this%greenr,2) /= ubound(backup%greenr,2)) then
        deallocate(backup%greenr)
        allocate(backup%greenr(ubound(this%greenr,1),ubound(this%greenr,2)))
      end if
    else
      allocate(backup%greenr(ubound(this%greenr,1),ubound(this%greenr,2)))
    end if

    ! Save the Green's functions to the object
    backup % greenr = this % greenr
  end subroutine

  pure subroutine material_load(this, backup)
    ! Imports the state of the material from a different object.
    class(material), intent(inout) :: this
    class(material), intent(inout) :: backup

    ! Make sure enough memory is allocated
    if (allocated(this%greenr)) then
      if (ubound(this%greenr,1) /= ubound(backup%greenr,1) .or. ubound(this%greenr,2) /= ubound(backup%greenr,2)) then
        deallocate(this%greenr)
        allocate(this%greenr(ubound(backup%greenr,1),ubound(backup%greenr,2)))
      end if
    else
      allocate(this%greenr(ubound(backup%greenr,1),ubound(backup%greenr,2)))
    end if

    ! Load the Green's functions from the object
    this % greenr = backup % greenr
  end subroutine

  impure subroutine material_write_dos(this, unit, a, b)
    ! Writes the density of states as a function of position and energy to a given output unit.
    class(material), intent(in) :: this      ! Material that the density of states will be calculated from
    integer,         intent(in) :: unit      ! Output unit that determines where the information will be written
    real(dp),        intent(in) :: a, b      ! Left and right end points of the material
    real(dp)                    :: x         ! Current location
    integer                     :: n, m      ! Temporary loop variables

    if (minval(this%energy) < -1e-16_dp) then
      ! If we have data for both positive and negative energies, simply write out the data
      do m=1,size(this%location)
        x = a+1e-8 + ((b-1e-8)-(a+1e-8)) * this%location(m)
        do n=1,size(this%energy)
          write(unit,*) x, this%energy(n), this%greenr(n,m)%get_dos()
        end do
      end do
    else
      ! If we only have data for positive energies, assume that the negative region is symmetric
      do m=1,size(this%location)
        x = a+1e-8 + ((b-1e-8)-(a+1e-8)) * this%location(m)
        do n=size(this%energy),1,-1
          write(unit,*) x, -this%energy(n), this%greenr(n,m)%get_dos()
        end do
        do n=1,size(this%energy),+1
          write(unit,*) x, +this%energy(n), this%greenr(n,m)%get_dos()
        end do
      end do
    end if
  end subroutine
end module
