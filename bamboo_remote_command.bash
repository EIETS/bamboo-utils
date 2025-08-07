#!/bin/bash

function debug
{
    local IFS=
    [ -n "$DEBUG" ] && for v in "${@}"; do echo $v; done >&2
	 return 0
}

function sig_initial_quit
{
	trap "" SIGQUIT
	debug "Get quit message first time"
	kill -QUIT 0
}

function sig_subseqent_quit
{
	trap "" SIGTERM
	debug "Get quit message 2nd time or more"
	kill -TERM 0
}

function sig_initial_int
{
	trap "" SIGINT
	debug "Get INT message first time"
	kill -INT 0
}

function log_out
{
	local IFS=
	printf "%s\t%(%F %T)T\t%s\n" $1 -1 "${*:2}"
}

function bamboo_log_out
{
   local IFS=
   if [ "$1" = "error" ]; then
     printf "%b%s\t%s%b\n" "\e[31m" $1 "${*:2}" "\e[0m" >&3
   else
     printf "%s\t%s\n" $1 "${*:2}" >&3
   fi
}

function log_err
{
    local IFS=
    printf "error\t%(%F %T)T\t%s\n" -1 "${*:1}"
} >&2

function read_stages
{
	local IFS=#
	local reading=0
	while [ $reading -eq 0 ]
	do
		read stage comment
		reading=$?
		[[ "$stage" =~ ^[[:space:]]*$ ]] && continue
		[ -d $stage ] || {
			log_err "Missing stage $stage folder, ignore it first"
			continue
		}
		
		[ -f $stage/disabled.flag ] && {
			log_out "INFO" "found disabled.flag in this stage $stage, skipped"
			continue
      }
      stages[${#stages[@]}]=${stage}

		[ -f $stage/final.flag ] && {
			stage_final[$stage]="YES"
		}
		[ -d $stage/bamboo_jobs ] && {
			pushd $stage/bamboo_jobs > /dev/null
			local ajobs=
			for oned in *; do
			   [ -d $oned ] || continue
			   [ -f $oned/disabled.flag ] && {
				   log_out "INFO" "found disabled job $oned of stage $stage, skipped"
				   continue
			   }
			   [ -x $oned/bamboo_tasks.bash ] || {
				   log_err "job $oned of stage $stage do not have an excutable entry bamboo_tasks.bash, skipped"
				   continue
			   }
			   ajobs="$ajobs;$oned"
			done
			stage_jobs[$stage]=$ajobs
			popd > /dev/null
		}
	done
	return 0
} < $stage_sequence_file

function parse_arr_jobs
{
	local IFS=\;
	arr_jobs=($1)
	[ -z ${arr_jobs[0]} ] && unset arr_jobs[0]
	return 0
}

function parse_injectvar_file
{
	varfile=$1
	namespace="inject"
	local IFS=#
	local varsep="^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$"
	local reading=0
	while [ $reading -eq 0 ]
	do
		read vdef comment
		reading=$?
		[[ "$vdef" =~ ^[[:space:]]*$ ]] && continue
		[[ $vdef =~ $varsep ]] && {
			local vd="bamboo_${namespace}_${BASH_REMATCH[1]}=${BASH_REMATCH[2]}#$comment"
			export "$vd"
		}
	done < $varfile
	return 0
}

function update_var_file
{
	varfile=$1
	shift
	local IFS=#
	local varsep="^[[:space:]]*(export[[:space:]]+)?([^=[:space:]]+)=(.*)$"
	local reading=0
	local -A varr
	while [ $reading -eq 0 ]
	do
		read vdef comment
		reading=$?
		[[ "$vdef" =~ ^[[:space:]]*$ ]] && continue
		[[ $vdef =~ $varsep ]] && {
			varr[${BASH_REMATCH[2]}]=${BASH_REMATCH[3]}
		}
	done < $varfile
	local IFS=" "
	for uv in "$@"; do
	    [ -z ${!uv} ] && continue
	    printf -v varr[$uv] "%q" "${!uv}"
	done
	for v in ${!varr[@]}; do
      echo "export $v=${varr[$v]}"
	done > $varfile
	return 0
}

# run script in remote site,
# usage: ssh_local_scripts script1 script2
#        ssh_local_scripts env_scripts - < shell_scripts
#                be aware - means scripts from input
# env setup before call this function
#     SSHDEST remote host name/IP , or format as USER@HOST
#     SSHPASS password for destination
function ssh_local_scripts
{
	[ -z "$SSHPASS" ] && {
		echo "Need SSHPASS setup" >&2
		return 1
	}
	[ -z "$SSHDEST" ] && {
		echo "Need SSHDEST setup" >&2
		return 1
	}

	{ echo "export bamboo_build_working_directory=${bamboo_build_working_directory}"; echo "export JOB_WORKSPACE=${JOB_WORKSPACE}"; cat "$@"; } | sshpass -e ssh -o "ServerAliveCountMax=25" -o "ServerAliveInterval=60" $SSHDEST
}

function ssh_xterm_local_scripts
{
	[ -z "$SSHPASS" ] && {
		echo "Need SSHPASS setup" >&2
		return 1
	}
	[ -z "$SSHDEST" ] && {
		echo "Need SSHDEST setup" >&2
		return 1
	}

	{ echo "export bamboo_build_working_directory=${bamboo_build_working_directory}"; echo "export JOB_WORKSPACE=${JOB_WORKSPACE}"; cat "$@"; } | sshpass -e ssh -o "ServerAliveCountMax=25" -o "ServerAliveInterval=60" -tt $SSHDEST
}

# copy files to/from remote by scp,
# usage: ssh_scp files... dest
#        if files and dest has no USER@HOST: format, dest will be prefixed with $SSHDEST which will copy files to remote by default
# env setup before call this function
#     SSHDEST remote host name/IP , or format as USER@HOST
#     SSHPASS password for destination
function ssh_scp
{
	[ -z "$SSHPASS" ] && {
		echo "Need SSHPASS setup" >&2
		return 1
	}
	[ -z "$SSHDEST" ] && {
		echo "Need SSHDEST setup" >&2
		return 1
	}
	local target=""
	local src="$@"
	[ $# -gt 1 ] && {
		target=${@: -1}
		[[ "$*" =~ [@:] ]] || target=${SSHDEST}:$target
		src="${@:1:$#-1}"
	}
	sshpass -e scp $src $target
}

function run_task
{
   local task_script=$@
   local iseset=""
   [[ "$-" =~ e ]] && {
      iseset="Y"
      set +e
   }
   bamboo_log_out "INFO" "Start task $task_script of job ${bamboo_shortJobName} on $SSHDEST..."
   log_out "INFO" "Start task $task_script of job ${bamboo_shortJobName} on $SSHDEST..."
   ssh_local_scripts ${bamboo_variables_file} ${bamboo_plan_variables_file} ${task_script}
   local task_result=$?
   if [ $task_result -eq 0 ]; then
      bamboo_log_out "INFO" "Finished task ${task_script} of job ${bamboo_shortJobName} with result: Success"
      log_out "INFO" "Finished task ${task_script} of job ${bamboo_shortJobName} with result: Success"
   else
      bamboo_log_out "error" "Failing task since return code of [${task_script}] was ${task_result} while expected 0"
      bamboo_log_out "error" "Finished task '${task_script}' of job ${bamboo_shortJobName} with result: Failed"
      log_out "error" "Failing task since return code of [${task_script}] was ${task_result} while expected 0"
      log_out "error" "Finished task '${task_script}' of job ${bamboo_shortJobName} with result: Failed"
   fi
   [ "$iseset" = "Y" ] && set -e
   return $task_result
}

function run_xterm_task
{
   local task_script=$@
   local iseset=""
   [[ "$-" =~ e ]] && {
      iseset="Y"
      set +e
   }
   bamboo_log_out "INFO" "Start task $task_script of job ${bamboo_shortJobName} on $SSHDEST with xterm..."
   log_out "INFO" "Start task $task_script of job ${bamboo_shortJobName} on $SSHDEST with xterm..."
   ssh_xterm_local_scripts ${bamboo_variables_file} ${bamboo_plan_variables_file} ${task_script}
   local task_result=$?
   if [ $task_result -eq 0 ]; then
      bamboo_log_out "INFO" "Finished task ${task_script} of job ${bamboo_shortJobName} with result: Success"
      log_out "INFO" "Finished task ${task_script} of job ${bamboo_shortJobName} with result: Success"
   else
      bamboo_log_out "error" "Failing task since return code of [${task_script}] was ${task_result} while expected 0"
      bamboo_log_out "error" "Finished task '${task_script}' of job ${bamboo_shortJobName} with result: Failed"
      log_out "error" "Failing task since return code of [${task_script}] was ${task_result} while expected 0"
      log_out "error" "Finished task '${task_script}' of job ${bamboo_shortJobName} with result: Failed"
   fi
   [ "$iseset" = "Y" ] && set -e
   return $task_result
}

function run_job
{
	log_out "simple" "$bamboo_planName - Build #$bamboo_buildNumber ($bamboo_buildKey-$bamboo_buildNumber) started building on agent $bamboo_agent_host"
	log_out "simple" "Build working directory is $job_folder"
	log_out "simple" "Executing build $bamboo_planName - Build #$bamboo_buildNumber ($bamboo_planKey-$bamboo_shortJobKey-$bamboo_buildNumber)"
	log_out "simple" "the current path when run job is $(pwd)"
	./bamboo_tasks.bash
	ret=$?
	./bamboo_final_tasks.bash
	return $ret
} > ${bamboo_log_dir}/${bamboo_buildKey}.log 2>&1

declare -a stages
declare -A stage_final
declare -A stage_jobs

export -f parse_injectvar_file
export -f ssh_local_scripts
export -f ssh_xterm_local_scripts
export -f ssh_scp
export -f bamboo_log_out
export -f run_task
export -f run_xterm_task
export -f log_out

export bamboo_utils_path=$(cd "$(dirname "$0")";pwd)
export bamboo_plan_workspace=$(cd ${bamboo_utils_path}/../..;pwd)
export bamboo_stages_path=$(cd ${bamboo_plan_workspace}/scriptrepos/bamboo_stages; pwd)
export bamboo_variables_file="${bamboo_plan_workspace}/bamboo_variables.sh"
if [ -f ${bamboo_stages_path}/plan_variables.sh ]; then
  export bamboo_plan_variables_file=${bamboo_stages_path}/plan_variables.sh
fi
stage_sequence_file="stage.sequence"

# these variables update from bamboo_variables_file
bamboo_planKey=
bamboo_buildKey=
bamboo_shortJobKey=
bamboo_buildNumber=
bamboo_planName=
bamboo_agent_host=$(hostname)

# creates 3 as alias for 1,for bamboo_tasks.bash to echo tasks to bamboo log
exec 3>&1
update_var_file ${bamboo_variables_file} bamboo_utils_path bamboo_plan_workspace bamboo_stages_path bamboo_log_dir bamboo_variables_file bamboo_plan_variables_file bamboo_agent_host
source ${bamboo_variables_file}
export artifact_path=${bamboo_plan_workspace}/artifacts
export bamboo_log_dir="$bamboo_plan_workspace/logs"
[ -d $bamboo_log_dir ] || {
	mkdir -p $bamboo_log_dir
}

[ -d $artifact_path ] || {
	mkdir -p $artifact_path
}


[ -z $bamboo_buildKey ] && {
	log_err "missing build key environment, ABORT!"
    exit 1
}
bamboo_buildKey_pre=${bamboo_buildKey%${bamboo_shortJobKey}}

cd $bamboo_stages_path
[ -r $stage_sequence_file ] || {
	log_err "missing stage define $stage_sequence_file, ABORT!"
    exit 1
}

trap sig_initial_quit SIGQUIT
trap sig_subseqent_quit SIGTERM
read_stages
debug ${stages[@]}
result_flag=0

for stage in "${stages[@]}"
do
	stage_folder="${bamboo_stages_path}/${stage}"
	[  -x "$stage_folder" ] || {
        log_err "Can't find the directory $stage_folder"
        exit 1
	}
	[ $result_flag -ne 0 -a "${stage_final[$stage]}" != "YES" ] && continue
	cd $stage_folder/bamboo_jobs

	stage_result=0
	unset stage_job_pids
	unset arr_jobs
	declare -a arr_jobs
	declare -A stage_job_pids
	parse_arr_jobs "${stage_jobs[$stage]}"
	debug "${arr_jobs[@]}"
	for cjob in "${arr_jobs[@]}"; do
		job_folder=$stage_folder/bamboo_jobs/$cjob
		export bamboo_build_working_directory=$job_folder
		cd $job_folder
		bamboo_shortJobKey=$cjob
		bamboo_buildKey="$bamboo_buildKey_pre$bamboo_shortJobKey"
		bamboo_log_out "INFO" "Running job $cjob of stage $stage ..."
		export bamboo_shortJobName=$cjob
		run_job $cjob&
		stage_job_pids[$cjob]=$!
		echo $! > bamboo_job.pid
		[ -f bamboo_inject.result.vars ] && parse_injectvar_file bamboo_inject.result.vars
	done
	unset term_job_pid
	while [ ${#stage_job_pids[@]} -ne 0 ]
	do
		wait -n
		for cjob in "${arr_jobs[@]}"; do
			job_pid=${stage_job_pids[$cjob]}
			[ -n $job_pid ] && [ ! -d "/proc/$job_pid" ] && {
				term_job=$cjob
				term_job_pid=$job_pid
				unset stage_job_pids[$cjob]
				break
			}
		done
		if [ -n $term_job_pid ]; then
			wait $term_job_pid
			# 1st wait maybe break by one signal, need 2nd wait
			wait $term_job_pid
			result=$?
			if [ $result -eq 0 ]; then
				bamboo_log_out "INFO" "Finished job '$term_job' with result: Success"
			else
				bamboo_log_out "error" "Finished job '$term_job' with result: Failed, code = $result"
			fi
			[ $result -ne 0 -a $stage_result -eq 0 ] && stage_result=$result
		fi
	done
	[ $stage_result -ne 0 ] && result_flag=1
	if [ $stage_result -eq 0 ]; then
      bamboo_log_out "INFO" "Finished stage '$stage' with result: Success"
	else
      bamboo_log_out "error" "Finished stage '$stage' with result: Failed, code = $stage_result"
	fi
done
exit $result_flag
