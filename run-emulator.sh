
# Run emulator
run_emulator()
{
    local android_api=$1
    log_info "Starting emulator for SDK $android_api"
    docker run -d -p 5555:5555 -p 5900:5900 --name android softsam/android-${android_api}
}

# Run appium server
run_appium_server()
{
    log_info "Starting appium server"
    docker run -d --link android:appium2android -p 4723:4723 --name appium -e APPIUM_ARGS="--suppress-adb-kill-server" -v ${APK_DIR}:/apk softsam/appium
}

# Wait for the emulator boot sequence to be over
wait_for_emulator()
{
    local bootanim=""
    until [[ "$bootanim" =~ "stopped" ]]; do
       bootanim=`docker exec appium adb -e shell getprop init.svc.bootanim 2>&1`
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
       docker exec appium adb connect android:5555
       device=`docker exec appium adb devices|awk 'NR>1 {print $1}'`
       sleep 1
    done
}

run_tests_on_emulator()
{
    local sdk_list=$@
    for sdk_version in $sdk_list
    do
        log_info "Starting test on emulator SDK=${sdk_version}"
        run_emulator $sdk_version
        run_appium_server
        log_info "Wait for appium server to be ready"
        sleep 10
        connect_appium_to_emulator
        wait_for_emulator
        local device=emulator-${sdk_version}
        local output_dir=$OUTPUT_DIR/$device
        if [ ! -d $output_dir ]
        then
            mkdir $output_dir
        fi
        start_recording $output_dir
        run_tests $device $sdk_version $output_dir
        stop_recording
        docker rm -f appium
        docker rm -f android
        docker rm -f vncrecorder
    done
}

# Start to record the vnc feed of the emulator
# Argument: the output directory of the video
start_recording()
{
    local output_dir=$1
    log_info "Starting video recording"
    docker run -d --link android:vncrecorder2android --name vncrecorder -v ${output_dir}:/vnc softsam/vncrecorder -o /vnc/record.flv android
}

stop_recording()
{
    log_info "Stopping video recording"
    docker kill -s INT vncrecorder
}

