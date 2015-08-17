
# Run emulator
# First argument: The SDK version
# Second argument: The architecture (x86 or arm)
run_emulator()
{
    local android_api=$1
    local android_architecture=$2
    log_info "Starting emulator for SDK $android_api on architecture $android_architecture"
    docker pull softsam/android-${android_api}:latest
    local virtualization_options=""
    if [[ $android_architecture == "x86" ]]
    then
        virtualization_options="--privileged -v /dev/kvm:/dev/kvm"
    fi
    docker run -d -p 5555:5555 -p 5900:5900 -e http_proxy="$http_proxy" -e ANDROID_ARCH="$2" $virtualization_options --name $docker_android softsam/android-${android_api}:latest
}

# Run appium server
run_appium_server()
{
    log_info "Starting appium server"
    docker pull softsam/appium:latest
    docker run -d --link ${docker_android}:android -p 4723:4723 --name $docker_appium -e APPIUM_ARGS="--suppress-adb-kill-server" -v ${APK_DIR}:/apk -v ${ANDROID_LOCALES_APK}:${ANDROID_LOCALES_APK} softsam/appium:latest
}

# Wait for the emulator boot sequence to be over
wait_for_emulator()
{
    local bootanim=""
    until [[ "$bootanim" =~ "stopped" ]]; do
       bootanim=`docker exec $docker_appium adb -e shell getprop init.svc.bootanim 2>&1`
       echo "Waiting for emulator to start...$bootanim"
       sleep 1
    done
}

# Connect appium & emulator
connect_appium_to_emulator()
{
    log_info "Connect appium to emulator"
    local device=""
    while [[ "${device}" = "" ]]; do
       docker exec $docker_appium adb connect android:5555
       device=`docker exec $docker_appium adb devices|awk 'NR>1 {print $1}'`
       sleep 1
    done
}

run_tests_on_emulator()
{
    local sdk_list=$@
    for sdk_version in $sdk_list
    do
        run_emulator $sdk_version $architecture
        run_appium_server
        log_info "Wait for appium server to be ready"
        sleep 10
        connect_appium_to_emulator
        wait_for_emulator
        #local device=emulator-5554
        local device=android:5555
        local output_dir=$OUTPUT_DIR/emulator-${sdk_version}
        if [ ! -d $output_dir ]
        then
            mkdir $output_dir
        fi
        log_info "Installing locale change tool"
        install_locale_change_tool $device
        start_recording $output_dir
        run_tests_for_all_locales $device $sdk_version $output_dir
        stop_recording
        docker rm -f $docker_appium
        docker rm -f $docker_android
        docker rm -f $docker_vncrecorder
    done
}

# Start to record the vnc feed of the emulator
# Argument: the output directory of the video
start_recording()
{
    local output_dir=$1
    log_info "Starting video recording"
    docker pull softsam/vncrecorder:latest
    docker run -d --link ${docker_android}:android --name $docker_vncrecorder -v ${output_dir}:/vnc softsam/vncrecorder:latest -o /vnc/record.flv android
}

stop_recording()
{
    log_info "Stopping video recording"
    docker kill -s INT $docker_vncrecorder
}

