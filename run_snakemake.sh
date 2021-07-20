pipeline=$1
error_dir=$2

#handle yaml file
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

eval $(parse_yaml config/snakemake_config.yaml "config_")

# set timestamp
log_time=`date +"%Y%m%d_%H%M"`
s_time=`date +"%Y%m%d_%H%M%S"`

#remove trailing / on directories
output_dir=$(echo $config_output_dir | sed 's:/*$::')
source_dir=$(echo $config_source_dir | sed 's:/*$::')

#Run pipeline on cluster or locally
if [[ $pipeline = "cluster" ]] || [[ $pipeline = "local" ]]; then

  #create output dir
  if [ -d "${output_dir}" ]
    then
      echo
      echo "Output dir: ${output_dir}"
    else
      mkdir "${output_dir}"
      echo
      echo "Creating output dir: ${output_dir}"
    fi

  #create log dir
  if [ -d "${output_dir}/log" ]
  then
    mkdir "${output_dir}/log/${log_time}"
    echo
    echo "Pipeline re-run:"
  else
    mkdir "${output_dir}/log"
    mkdir "${output_dir}/log/${log_time}"
    echo
    echo "Pipeline initial run:"
  fi

  # copy config inputs for ref
  files_save=('config/snakemake_config.yaml' 'config/cluster_config.yml' 'config/index_config.yaml' ${config_multiplex_manifest} ${config_sample_manifest} 'workflow/Snakefile')

  for f in ${files_save[@]}; do
    IFS='/' read -r -a strarr <<< "$f"
    cp $f "${output_dir}/log/${log_time}/00_${strarr[-1]}"
  done

  #submit jobs to cluster
  if [[ $pipeline = "cluster" ]]; then
    sbatch --job-name="iCLIP" --gres=lscratch:200 --time=24:00:00 --output=${output_dir}/log/${log_time}/00_%j_%x.out --mail-type=BEGIN,END,FAIL \
    snakemake --use-envmodules --latency-wait 120  -s ${output_dir}/log/${log_time}/00_Snakefile --configfile ${output_dir}/log/${log_time}/00_snakemake_config.yaml \
    --printshellcmds --cluster-config ${output_dir}/log/${log_time}/00_cluster_config.yml --keep-going \
    --restart-times 1 --cluster "sbatch --gres {cluster.gres} --cpus-per-task {cluster.threads} \
    -p {cluster.partition} -t {cluster.time} --mem {cluster.mem} \
    --job-name={params.rname} --output=${output_dir}/log/${log_time}/{params.rname}.out" -j 500 --rerun-incomplete

  #submit jobs locally
  else
    #remove iCount dir if it already exist - will cause error in demux
    if [ -d "/tmp/iCount" ]; then 
      rm -r /tmp/iCount/ 
    fi
    snakemake -s ${output_dir}/log/${log_time}/00_Snakefile --use-envmodules --configfile ${output_dir}/log/${log_time}/00_snakemake_config.yaml \
    --printshellcmds --cluster-config ${output_dir}/log/${log_time}/00_cluster_config.yml --cores 8
  fi
#Unlock pipeline
elif [[ $pipeline = "unlock" ]]; then
  snakemake -s workflow/Snakefile --use-envmodules --unlock --cores 8 --configfile config/snakemake_config.yaml
#Run github actions
elif [[ $pipeline = "test" ]]; then
  snakemake -s workflow/Snakefile --configfile .tests/snakemake_config.yaml \
  --printshellcmds --cluster-config config/cluster_config.yml -npr
#Create DAG
elif [[ $pipeline = "DAG" ]]; then
  snakemake -s workflow/Snakefile --configfile .tests/snakemake_config.yaml --rulegraph | dot -Tpdf > dag.pdf
#Create error report
elif [[ $pipeline = "error" ]]; then
  echo
  echo "creating error log"
  grep -i error ${error_dir}*_iCLIP.out > ${error_dir}error_log.txt
  echo "view error log: cat ${error_dir}error_log.txt"
#Dry-run pipeline
else
  #run snakemake
  snakemake -s workflow/Snakefile --configfile config/snakemake_config.yaml \
  --printshellcmds --cluster-config config/cluster_config.yml -npr
fi