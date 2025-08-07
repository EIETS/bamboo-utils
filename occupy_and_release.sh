function echo_help_occupy {
    cat <<-EOF
    Help:
    occupy provides three parameter forms:
    1.occupy_testbed -bedid <bedid> -retries <retries>
    2.occupy_testbed -poolname <poolname> -host <host> -retries <retries>
    3.occupy_testbed -poolname <poolname> -retries <retries>

    Parameters explain:
    first parameter form:
    -bedid : Provide the id of testbed(Unsigned integer).
    second and third parameter form:
    -poolname : Provide the pool name of testbed.
    -host <host> Provide the host name of testbed.
If provided, poolname and host will uniquely mark testbed;otherwise, it will find a idle testbed according to the poolname.

    Nonessential parameters:
    -retries <retries> Display indicates the number of cycles, default is 120(Unsigned integer).
    
    One example:
        occupt_testbed -bedid 1
        occupy_testbed -poolname gpon,gpon1
    Use '-h' to show this information.
EOF
}

function echo_help_release {
    cat <<-EOF
    Help:
    release provides two parameter forms:
    1.release_testbed -bedid <bedid>
    2.release_testbed -poolname <poolname> -host <host>

    Parameters explain:
    first parameter form:
    -bedid : Provide the id of testbed(Unsigned integer).
    second parameter form:
    -poolname : Provide the pool name of testbed.
    -host : Provide the host name of testbed (poolname and host will uniquely mark testbed).
    
    One example:
        release_testbed -poolname gpon -host gponhost.calix.local
    Use '-h' to show this information.
EOF
}

declare -A para

function parsePara {
    echo -e "Action: Running me:\n\t$0 $*"
    arr=("$*")
    # echo ${arr[@]} ${#arr[*]}
    key=t
    for i in $arr
    do
        # if the paremeters include '-h', which will echo help and do nothing else.
        if [[ $i = "-h" ]];then
            help="help"
            return 0
        fi
        # the parameters' name need start with '-'
        if [[ $i = -* ]];then
            val=${i:1}
            echo "$val" | grep [^0-9] >/dev/null && {
                [[ -n ` eval echo "$value" ` ]] && para["$key"]=` eval echo "$value" `; # Assign the value of the previous parameter
                value="";
                key=$i;
            } || { # negative
                value="$value $i";
            }
        else
            value="$value $i"
        fi
    done
    [[ -n ` eval echo "$value" ` ]] && para["$key"]=` eval echo "$value" ` # At the end of the cycle, assign the value of the last parameter
}

function getOpts {
    for key in "${!para[@]}"; do
        # para["$key"]=`eval echo ${para["$key"]}` 
        # echo $key ${para["$key"]}
        case $key in
            -bedid )
                bedid=${para[$key]}
                listid=( $bedid )
                lenid=${#listid[*]}
                # echo $lenid
                [ $lenid -gt 1 ] 2>/dev/null && { echo "the value of 'bedid' requirts just one value! please input one value just." ; exit 0; }
                [ $bedid -gt 0 ] 2>/dev/null || { echo "the value of 'bedid' requirts a greater than 0! please input a unsigned integer(>0)." ; exit 0; }
                ;;            
            -poolname )
                poolname=${para[$key]}
                echo "poolname=${poolname}"
                ;;
            -host )
                host=${para[$key]}
                ;;
            -retries )
                retries=${para[$key]}
                listret=( $retries )
                lenret=${#listret[*]}
                # echo $lenid
                [ $lenret -gt 1 ] 2>/dev/null && { echo "the value of 'retries' requirts just one greater than 0 integer value! Set retries=120 already." ; retries=120; }
                [ $retries -gt 0 ] 2>/dev/null || { echo "the value of 'retries' requirts a greater than 0! Set retries=120 already." ; retries=120; }
                ;;            
            -bamboourl )
                bamboourl=${para[$key]}
                [ -z $bamboourl ] && bamboourl="http://cdc-bamboo2.calix.local"
                
        esac
    done
}


function occupy_by_bedid {
    [[ "$-" =~ e ]] && {
        iseset="Y"
        set +e
    }
    [ -z $retries ] && retries=120 
    testbed_host='timeout'
    #modify here to update the loop times.
    for((i=$retries;i>=0;i--))
    do
        echo "Execue curl --data \"bedid=${bedid}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}\" http://cdc-tbedmng.calix.local/web/index.php?r=api/occupy"
        json=`curl --data "bedid=${bedid}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}" http://cdc-tbedmng.calix.local/web/index.php?r=api/occupy`
        ret=$?
        echo $json
        bamboo_log_out "INFO" "occupy_testbed json=$json"
        [ $ret -ne 0 ] && bamboo_log_out "error" "Occupy the testbed of bedid ${bedid} failed.return not equal 0." && break
        key=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'key'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
        if [[ "success" == $key ]];then
            testbed_bedid=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'bedid'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            bedid=${testbed_bedid}
            testbed_poolname=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'poolname'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            testbed_host=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'testbedhost'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            testbed_properties=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'properties'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            bamboo_log_out "INFO" "Occupy pool $testbed_poolname Success! bedid=$bedid testbed_host=$testbed_host properties=$testbed_properties "
            echo "Occupy pool $testbed_poolname Success! bedid=$bedid testbed_host=$testbed_host properties=$testbed_properties "
            [ "$iseset" = "Y" ] && set -e 
            return 0
        elif [[ "fail" == $key ]];then
            message=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'message'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            if [[ $message =~ busy ]];then
                log_out "INFO" "$message"
                log_out "INFO" "Will try to occupy testbed in bedid $bedid 1 minute later,$i times left."
                #modify here to update sleep time between curl.
                sleep 60
                continue
            else
                bamboo_log_out "error" "3 Occupy the testbed of bedid ${bedid} failed.look at logs for detail.${message}"
                break
            fi

        else
            bamboo_log_out "error" "4 Occupy the testbed of bedid ${bedid} failed.look at logs for detail."
            #return "0 fail"
            testbed_host='fail'
            retries=120
            continue
        fi
    done
    [[ "fail" == $key && $message =~ busy ]] && bamboo_log_out "error" "5 Occupy the testbed of bedid ${bedid} failed.it is busy,timeout."
    [ "$iseset" = "Y" ] && set -e
    return 1
}

function occupy_by_poolnameandhost {
    [[ "$-" =~ e ]] && {
        iseset="Y"
        set +e
    }
    [ -z $retries ] && retries=120 
    testbed_host='timeout'
    #modify here to update the loop times.
    for((i=$retries;i>=0;i--))
    do
        echo "Execue curl --data \"poolname=${poolname}&host=${host}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}\" http://cdc-tbedmng.calix.local/web/index.php?r=api/occupy"
        json=`curl --data "poolname=${poolname}&host=${host}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}" http://cdc-tbedmng.calix.local/web/index.php?r=api/occupy`
        ret=$?
        echo $json
        bamboo_log_out "INFO" "occupy_testbed json=$json"
        [ $ret -ne 0 ] && bamboo_log_out "error" "Occupy the testbed of poolname ${poolname} and host ${host} failed.return not equal 0." && break
        key=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'key'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
        if [[ "success" == $key ]];then
            testbed_bedid=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'bedid'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            bedid=${testbed_bedid}
            testbed_properties=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'properties'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            bamboo_log_out "INFO" "Occupy poolname ${poolname} and host ${host} Success! bedid=$testbed_bedid properties=$testbed_properties "
            echo "Occupy poolname ${poolname} and host ${host} Success! bedid=$testbed_bedid properties=$testbed_properties "
            [ "$iseset" = "Y" ] && set -e 
            return 0
        elif [[ "fail" == $key ]];then
            message=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'message'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            if [[ $message =~ busy ]];then
                log_out "INFO" "$message"
                log_out "INFO" "Will try to occupy testbed in poolname ${poolname} and host ${host} 1 minute later,$i times left."
                #modify here to update sleep time between curl.
                sleep 60
                continue
            else
                bamboo_log_out "error" "3 Occupy the testbed of poolname ${poolname} and host ${host} failed.look at logs for detail.${message}"
                break
            fi

        else
            bamboo_log_out "error" "4 Occupy the testbed of poolname ${poolname} and host ${host} failed.look at logs for detail."
            #return "0 fail"
            testbed_host='fail'
            retries=120
            continue
        fi
    done
    [[ "fail" == $key && $message =~ busy ]] && bamboo_log_out "error" "5 Occupy the testbed of poolname ${poolname} and host ${host} failed.it is busy,timeout."
    [ "$iseset" = "Y" ] && set -e
    return 1
}

function occupy_by_poolname {
    [[ "$-" =~ e ]] && {
        iseset="Y"
        set +e
    }
    [ -z $retries ] && retries=120 
    testbed_host='timeout'
    poolnames=(${poolname//,/ })
    #modify here to update the loop times.
    for((i=$retries;i>=0;i--))
    do
        for pool in ${poolnames[*]};do
            echo "Execue curl --data \"poolname=${pool}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}\" http://cdc-tbedmng.calix.local/web/index.php?r=api/occupy"
            json=`curl --data "poolname=${pool}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}" http://cdc-tbedmng.calix.local/web/index.php?r=api/occupy`
            ret=$?
            echo $json
            bamboo_log_out "INFO" "occupy_testbed json=$json"
            [ $ret -ne 0 ] && bamboo_log_out "error" "Occupy the testbed of pool ${pool} failed.return not equal 0." && break
            key=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'key'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
            if [[ "success" == $key ]];then
                testbed_host=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'testbedhost'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
                testbed_bedid=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'bedid'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
                bedid=${testbed_bedid}
                testbed_properties=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'properties'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
                bamboo_log_out "INFO" "Occupy pool $pool Success! bedid=$bedid testbed_host=$testbed_host properties=$testbed_properties "
                [ "$iseset" = "Y" ] && set -e 
                return 0
            elif [[ "fail" == $key ]];then
                message=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'message'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
                
            else
                bamboo_log_out "error" "4 Occupy the testbed of pool ${pool} failed.look at logs for detail."
                #return "0 fail"
                testbed_host='fail'
                retries=120
                continue
            fi
        done
        if [[ $message =~ busy ]];then
            log_out "INFO" "$message"
            log_out "INFO" "Will try to occupy testbed in pool $pool 1 minute later,$i times left."
            #modify here to update sleep time between curl.
            sleep 60
            continue
        else
            bamboo_log_out "error" "3 Occupy the testbed of pool ${pool} failed.look at logs for detail.${message}"
            break
        fi
    done
    [[ "fail" == $key && $message =~ busy ]] && bamboo_log_out "error" "5 Occupy the testbed of pool ${poolname} failed.testbeds are all busy,timeout."

    [ "$iseset" = "Y" ] && set -e
    # [ $testbed_bedid -eq 0 ] && return 1 || return 0
    return 1
}

function occupy_testbed
{
    parsePara "$@"
    # echo "bedid=$bedid" "help=-$help-"
    if [[ $help == "help" ]];then
        echo_help_occupy
        exit 0
    fi
    getOpts

    if [[ $bedid -gt 0 ]];then
        occupy_by_bedid
    elif [[ -n $poolname && -n $host ]];then
        occupy_by_poolnameandhost
    elif [[ -n $poolname ]];then
        occupy_by_poolname
    else
        echo_help_occupy
        exit 0
    fi
    return $?
}

function release_by_bedid
{
    [[ "$-" =~ e ]] && {
        iseset="Y"
        set +e
    }
    echo "Execue curl --data \"bedid=${bedid}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}\" http://cdc-tbedmng.calix.local/web/index.php?r=api/release"
    json=`curl --data "bedid=${bedid}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}" http://cdc-tbedmng.calix.local/web/index.php?r=api/release`
    ret=$?
    echo $json
    bamboo_log_out "INFO" "release_testbed json=$json"
    [ $ret -ne 0 ] && bamboo_log_out "error" "Occupy the testbed of bedid ${bedid} failed.return not equal 0." && break
    key=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'key'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
    if [[ "success" == $key ]];then
        log_out "INFO" "Release this testbed ${bedid} success"
        bamboo_log_out "INFO" "Release this testbed ${bedid} success"
        [ "$iseset" = "Y" ] && set -e
        return 0
    fi
    log_err "Release this testbed bedid=${bedid} fail,Please contact admin to release it manually!"
    bamboo_log_out "error" "Release this testbed bedid=${bedid} fail,Please contact admin to release it manually!"
    [ "$iseset" = "Y" ] && set -e
    return 1
}

function release_by_poolnameandhost {
    [[ "$-" =~ e ]] && {
        iseset="Y"
        set +e
    }
    echo "Execue curl --data \"poolname=${poolname}&host=${host}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}\" http://cdc-tbedmng.calix.local/web/index.php?r=api/release"
    json=`curl --data "poolname=${poolname}&host=${host}&bamboouser=${bamboo_trigger_user}&plankey=${bamboo_planKey}-${bamboo_buildNumber}&bamboourl=${bamboourl}" http://cdc-tbedmng.calix.local/web/index.php?r=api/release`
    ret=$?
    echo $json
    bamboo_log_out "INFO" "release_testbed json=$json"
    [ $ret -ne 0 ] && bamboo_log_out "error" "Occupy the testbed of poolname ${poolname} and host ${host} failed.return not equal 0." && break
    key=$(echo "${json}" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'key'\\\042/){print $(i+1)}}}' | tr -d '\\"' | sed -n 1p)
    if [[ "success" == $key ]];then
        log_out "INFO" "Release this testbed poolname=${poolname} and host=${host} success"
        bamboo_log_out "INFO" "Release this testbed poolname=${poolname} and host=${host} success"
        [ "$iseset" = "Y" ] && set -e
        return 0
    fi
    log_err "Release this testbed poolname=${poolname} and host=${host} fail,Please contact admin to release it manually!"
    bamboo_log_out "error" "Release this testbed poolname=${poolname} and host=${host} fail,Please contact admin to release it manually!"
    [ "$iseset" = "Y" ] && set -e
    return 1
}

function release_testbed {
    parsePara "$@"
    unset para["-retries"] # relese operation don't need deal with parameter 'retries'
    # echo "bedid=$bedid" "help=-$help-"
    if [[ $help == "help" ]];then
        echo_help_release
        exit 0
    fi
    getOpts

    if [[ $bedid -gt 0 ]];then
        release_by_bedid
    elif [[ -n $poolname && -n $host ]];then
        release_by_poolnameandhost
    else
        echo_help_release
        exit 0
    fi
    return $?
}
