!---------!
! WARNING ! DOESN'T WORK WITH Y-PARALLELISATION
!---------!

! Scalar SCAL was never assigned any value
! Element connectivity matrix is still empty
! one cool thing would be to parallelise the file format as well
! check out: https://vtk.org/wp-content/uploads/2015/04/file-formats.pdf

! also, a better argument parsing might be nice (like, taking mutltiple fields at once)


program out2vtk
! convert out file to VTK (XML) format for paraview
! syntax:
! mpirun -np 1 out2vtk Dati.cart.xx.out
use dnsdata
implicit none

character(len=32) :: cmd_in_buf ! needed to parse arguments

integer*8 :: iv, ix, iz, iy, pos
integer :: ierror, ii
integer :: ndim, nxtot, nytot, nztot, nxloc, nyloc, nzloc
integer*8 :: nnos, nnos_local      
real*4, dimension(:,:), allocatable :: xyz, vec ! watch out for this type! must be the same as 
real*4, dimension(:), allocatable :: scal

integer, dimension(:), allocatable :: local_zsize_arr
integer :: z_start = 0

type(MPI_Datatype) :: wtype_3d, type_towrite ! , wtype_scalar


    ! read arguments
    if (COMMAND_ARGUMENT_COUNT() < 1) then
        print *, 'ERROR: please provide one input file as command line argument.'
        stop
    end if
    call get_command_argument(1, cmd_in_buf)
    read(cmd_in_buf, *) fname

    ! Init MPI
    call MPI_INIT(ierr)
    call MPI_COMM_RANK(MPI_COMM_WORLD,iproc,ierr)
    call MPI_COMM_SIZE(MPI_COMM_WORLD,nproc,ierr)
    call read_dnsin()
    call init_MPI(nx+1,nz,ny,nxd+1,nzd)
    call init_memory(.TRUE.)
    call init_fft(VVdz,VVdx,rVVdx,nxd,nxB,nzd,nzB)



    !------------!
    ! PARAMETERS !
    !------------!

    ndim  = 3  ! number of spatial dimension

    ! GLOBAL QUANTITIES, which is, overall sizes of stuff
    nxtot = 2*nxd  ! no. points
    nytot = (ny + 1)   ! no. points
    nztot = nzd      ! no. points
    nnos  = nxtot*nytot*nztot             ! number of nodes

    ! things that are local to each process
    ! number of points in each direction
    nxloc = 2*nxd       ! these refer to UNIQUE data! It does not consider halo cells
    nyloc = min(ny,maxy)-max(0,miny)+1 ! these refer to UNIQUE data! It does not consider halo cells, nor ghost cells
    nzloc = nzB         ! these refer to UNIQUE data! It does not consider halo cells
    nnos_local = nxloc*nyloc*nzloc ! number of nodes OWNED BY PROCESS

    !-------------------!
    ! END OF PARAMETERS !
    !-------------------!



    ! allocate stuff
    allocate(xyz(ndim,nnos_local))    ! nodal coordinates
    allocate(vec(ndim,nnos_local))    ! vectorial field
    allocate(scal(nnos_local))        ! scalar field



    !---------------------------!
    ! MPI FILETYPES FOR WRITING !
    !---------------------------!

    ! each process tells the others how many local nodes it has
    allocate(local_zsize_arr(nproc))
    local_zsize_arr(iproc+1) = nzloc
    do ii=0,(nproc-1)
        call MPI_BCAST(local_zsize_arr(ii+1),1,MPI_INTEGER,ii,MPI_COMM_WORLD)
    end do
    ! each process calculates its starting position in the global nodes list
    do ii=0,(iproc-1)
        z_start = z_start + local_zsize_arr(ii+1)
    end do

    ! data owned by each process that needs to be written
    CALL MPI_Type_create_subarray(3, [nxloc, nyloc, nzloc], [nxloc, nyloc, nzloc], [0, 0, 0], MPI_ORDER_FORTRAN, MPI_REAL, type_towrite)
    CALL MPI_Type_commit(type_towrite, ierror)
    
    ! XYZ AND VEC - for writing (setting view)
    ! 0) number of dimensions of array you want to write
    ! 1) size along each dimension of the WHOLE array ON DISK
    ! 2) size of the PORTION of array TO BE WRITTEN BY EACH PROCESS
    ! 3) starting position of each component; !!! IT'S ZERO BASED !!!
    CALL MPI_Type_create_subarray(4, [3, nxtot, nytot, nztot], [3, nxloc, nyloc, nzloc], [0, 0, 0, z_start], MPI_ORDER_FORTRAN, MPI_REAL, wtype_3d)
    !                             0)            1)                        2)                    3)
    CALL MPI_Type_commit(wtype_3d, ierror)

    ! SCALAR - for writing (setting view)
    ! 0) number of dimensions of array you want to write
    ! 1) size along each dimension of the WHOLE array ON DISK
    ! 2) size of the PORTION of array TO BE WRITTEN BY EACH PROCESS
    ! 3) starting position of each component; !!! IT'S ZERO BASED !!!
!   CALL MPI_Type_create_subarray(3, [nxtot, nytot, nztot], [nxloc, nyloc, nzloc], [0, 0, z_start], MPI_ORDER_FORTRAN, MPI_REAL, wtype_scalar)
!   !                             0)         1)                     2)                 3)
!   CALL MPI_Type_commit(wtype_scalar, ierror)

    !----------------------------------!
    ! END OF MPI FILETYPES FOR WRITING !
    !----------------------------------!



    ! read file
    CALL read_restart_file(fname,V)

    ! for each y plane
    do iy = miny,maxy ! skips halo cells: only non-duplicated data
        
        ! skip ghost cells
        if (iy < 0) cycle
        if (iy > ny+1) cycle
        
        ! do fourier transform
        VVdz(1:nz+1,1:nxB,1:3,1)=V(iy,0:nz,nx0:nxN,1:3);         VVdz(nz+2:nzd-nz,1:nxB,1:3,1)=0;
        VVdz(nzd+1-nz:nzd,1:nxB,1:3,1)=V(iy,-nz:-1,nx0:nxN,1:3); 
        DO iV=1,3
            CALL IFT(VVdz(1:nzd,1:nxB,iV,1))  
            CALL MPI_Alltoall(VVdz(:,:,iV,1), 1, Mdz, VVdx(:,:,iV,1), 1, Mdx, MPI_COMM_X)
            VVdx(nx+2:nxd+1,1:nzB,iV,1)=0;    CALL RFT(VVdx(1:nxd+1,1:nzB,iV,1),rVVdx(1:2*nxd+2,1:nzB,iV,1))
        END DO
        ! rVVdx is now containing the antitransform
        ! it has size 2*(nxd+1),nzB,6,6
        ! but you only need (1:2*nxd,1:nzB,1:3,1)

        ! convert velocity vector for each process
        do ix=1,2*nxd
            do iz = 1,nzB
                pos = ix + (iy-1)*2*nxd + (iz-1)*2*nxd*(ny+1) !THIS ORDER IS IMPORTANT! x index must be varying first, then y, then z
                vec(:,pos) = rVVdx(ix,iz,:,1)
                xyz(1,pos) = (ix-1) * (2 * PI / alfa0)/(2*nxd-1)
                xyz(2,pos) = y(iy)
                xyz(3,pos) = (iz + nz0 - 2) * (2 * PI / beta0)/(nzd-1)
            end do
        end do

    end do
    
    call WriteXMLFormat(fname)

    ! realease memory
    CALL free_fft()
    CALL free_memory(.TRUE.) 
    CALL MPI_Finalize()



contains !-------------------------------------------------------------------------------------------------------------------



    subroutine WriteXMLFormat(fname) 

        character(len = 40) :: fname

        character :: buffer*200, lf*1, offset*16, str1*16, str2*16, str3*16, str33*16, str5*16, str6*16
        integer   :: ivtk = 9, dotpos
        real*4    :: float ! this must have same type of xyz and vec and stuff
        integer(C_SIZE_T) :: nbytes_vec, nbytes_xyz ! , nbytes_scal
        integer(C_SIZE_T) :: ioff1, ioff2 ! , ioff0
        integer(C_SIZE_T) :: disp

        type(MPI_File) :: fh
        TYPE(MPI_Status) :: status

        lf = char(10) ! line feed character

!       nbytes_scal   =         nnos * sizeof(float)
        nbytes_vec    = ndim  * nnos * sizeof(float)
        nbytes_xyz    = ndim  * nnos * sizeof(float)

!       ! offset for scalar
!       ioff0 = 0
        ! offset for vector
        ioff1 = 0 ! ioff0 + sizeof(nbytes_xyz) + nbytes_scal
        ! offset for points
        ioff2 = ioff1 + sizeof(nbytes_xyz) + nbytes_vec

        ! adapt filename
        dotpos = scan(trim(fname),".", BACK= .true.)
        if ( dotpos > 0 ) fname = fname(1:dotpos)//"vts"

        ! write xml
        if (has_terminal) then
            open(unit=ivtk,file=fname,form='binary')
                buffer = '<?xml version="1.0"?>'//lf                                                                                                  ; write(ivtk) trim(buffer)
                buffer = '<VTKFile type="StructuredGrid" version="0.1" byte_order="LittleEndian" header_type="UInt64">'//lf						  	                      ; write(ivtk) trim(buffer)
                write(str1(1:16), '(i16)') 1 ! x0
                write(str2(1:16), '(i16)') nxtot ! xn
                write(str3(1:16), '(i16)') 1 ! y0
                write(str33(1:16),'(i16)') nytot ! yn
                write(str5(1:16), '(i16)') 1 ! z0
                write(str6(1:16), '(i16)') nztot ! zn
                buffer = '  <StructuredGrid WholeExtent="'//str1//' '//str2//' '//str3//' '//str33//' '//str5//' '//str6//'">'//lf                   ; write(ivtk) trim(buffer)
                buffer = '    <Piece Extent="'//str1//' '//str2//' '//str3//' '//str33//' '//str5//' '//str6//'">'//lf                                ; write(ivtk) trim(buffer)
                buffer = '      <PointData> '//lf                                                                                                     ; write(ivtk) trim(buffer)
!               write(offset(1:16),'(i16)') ioff0
!               buffer = '         <DataArray type="Float32" Name="scalars" format="appended" offset="'//offset//'"           />'//lf                 ; write(ivtk) trim(buffer)
                write(offset(1:16),'(i16)') ioff1
                buffer = '         <DataArray type="Float32" Name="Velocity" NumberOfComponents="3" format="appended" offset="'//offset//'" />'//lf   ; write(ivtk) trim(buffer)
                buffer = '      </PointData>'//lf                                                                                                     ; write(ivtk) trim(buffer)
                buffer = '      <CellData>  </CellData>'//lf                                                                                          ; write(ivtk) trim(buffer)
                buffer = '      <Points>'//lf                                                                                                         ; write(ivtk) trim(buffer)
                write(offset(1:16),'(i16)') ioff2
                buffer = '        <DataArray type="Float32" Name="coordinates" NumberOfComponents="3" format="appended" offset="'//offset//'" />'//lf ; write(ivtk) trim(buffer)
                buffer = '      </Points>'//lf                                                                                                        ; write(ivtk) trim(buffer)
                buffer = '    </Piece>'//lf                                                                                                           ; write(ivtk) trim(buffer)
                buffer = '  </StructuredGrid>'//lf                                                                                                    ; write(ivtk) trim(buffer)
                buffer = '  <AppendedData encoding="raw">'//lf                                                                                        ; write(ivtk) trim(buffer)
                buffer = '_'                                                                                                                          ; write(ivtk) trim(buffer)
            close(ivtk)
        end if
        
!        ! write scalar
!
!        if (has_terminal) then
!            open(unit=ivtk,file=fname,form='binary',position='append')
!                write(ivtk) nbytes_scal
!            close(ivtk)
!        end if
!
!        print *, "Written xml"
!
!        CALL MPI_Barrier(MPI_COMM_WORLD) ! barrier so every process retrieves the same filesize
!        inquire(file=fname, size=disp) ! retrieve displacement
!        CALL MPI_Barrier(MPI_COMM_WORLD)
!
!        print *, "Writing scalar"
!
!        CALL MPI_File_open(MPI_COMM_WORLD, TRIM(fname), IOR(MPI_MODE_WRONLY, MPI_MODE_CREATE), MPI_INFO_NULL, fh)
!            CALL MPI_File_set_view(fh, disp, MPI_REAL, wtype_scalar, 'native', MPI_INFO_NULL)
!            CALL MPI_File_write_all(fh, scal, 1, type_towrite, status)
!        CALL MPI_File_close(fh)

        ! write vec

        if (has_terminal) then
            open(unit=ivtk,file=fname,form='binary',position='append')
                write(ivtk) nbytes_vec
            close(ivtk)
        end if

        print *, "Writing vector field"
        
        CALL MPI_Barrier(MPI_COMM_WORLD) ! barrier so every process retrieves the same filesize
        inquire(file=fname, size=disp) ! retrieve displacement
        CALL MPI_Barrier(MPI_COMM_WORLD)

        CALL MPI_File_open(MPI_COMM_WORLD, TRIM(fname), IOR(MPI_MODE_WRONLY, MPI_MODE_CREATE), MPI_INFO_NULL, fh)
            CALL MPI_File_set_view(fh, disp, MPI_REAL, wtype_3d, 'native', MPI_INFO_NULL)
            CALL MPI_File_write_all(fh, vec, 3, type_towrite, status)
        CALL MPI_File_close(fh)

        ! write xyz

        if (has_terminal) then
            open(unit=ivtk,file=fname,form='binary',position='append')
                write(ivtk) nbytes_xyz
            close(ivtk)
        end if

        print *, "Writing coordinates of points"

        CALL MPI_Barrier(MPI_COMM_WORLD) ! barrier so every process retrieves the same filesize
        inquire(file=fname, size=disp) ! retrieve displacement
        CALL MPI_Barrier(MPI_COMM_WORLD)

        CALL MPI_File_open(MPI_COMM_WORLD, TRIM(fname), IOR(MPI_MODE_WRONLY, MPI_MODE_CREATE), MPI_INFO_NULL, fh)
            CALL MPI_File_set_view(fh, disp, MPI_REAL, wtype_3d, 'native', MPI_INFO_NULL)
            CALL MPI_File_write_all(fh, xyz, 3, type_towrite, status)
        CALL MPI_File_close(fh)

        if (has_terminal) then
            open(unit=ivtk,file=fname,form='binary',position='append')
                buffer = lf//'  </AppendedData>'//lf;           write(ivtk) trim(buffer)
                buffer = '</VTKFile>'//lf;                      write(ivtk) trim(buffer)
            close(ivtk)
        end if

    end subroutine



end program






