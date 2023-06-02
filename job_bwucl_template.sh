#!/bin/sh
#SBATCH --job-name=cor5_1
#SBATCH -p multiple_il
#SBATCH -N 40 -n 2560
#SBATCH --time=72:00:00 
#SBATCH --mail-type=ALL --mail-user=your.email@kit.edu 

# load modules
module purge
module load compiler/intel
module load mpi/impi

# compile
cd channel
make clean
make
cd .. # go back to working directory

# run
mpiexec.hydra -bootstrap slurm channel/channel
