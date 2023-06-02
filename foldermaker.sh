echo "This script will create a folder with all needed input files for a new simulation."
echo "Please edit these input files after creation!"

chan_path="$(dirname -- "${BASH_SOURCE[0]}")" # relative path
chan_path="$(cd -- "${chan_path}" && pwd)" # absolutized and normalized

echo "Please enter the path where you want to create a new simulation folder."
echo "This directory needs to exist already!"
read parent_dir
echo ""
echo "Entering ${parent_dir}. Please enter the desired name of the simulation folder."
echo "This folder will be created!"
read sim_name
echo "Making ${parent_dir}/${sim_name}"
mkdir ${parent_dir}/${sim_name}
echo ""
echo "Copying channel, dns.in, coriolis.in"
cp -r ${chan_path} ${parent_dir}/${sim_name}/channel
cp ${chan_path}/dns.in ${parent_dir}/${sim_name}
cp ${chan_path}/body_forces/coriolis/coriolis.in ${parent_dir}/${sim_name}
echo ""
echo "Please specify restart file to be used. Absolute path is needed."
echo "Leave blank to skip this step."
read restart_file
if [[ ! -z "${restart_file}" ]]
then
    echo "Copying restart file"
    cp ${restart_file} ${parent_dir}/${sim_name}/Dati.cart.out
fi
echo ""
echo "All done! Please remember to adjust all input files according to your needs."