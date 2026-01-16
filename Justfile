# parse & plot keymap

default:
    @just --list --unsorted

config := absolute_path('config')
build := absolute_path('.build')
out := absolute_path('firmware')
draw := absolute_path('draw')

draw:
    #!/usr/bin/env bash
    set -euo pipefail
    keymap -c "{{ draw }}/config.yaml" parse -z "{{ config }}/base.keymap" --virtual-layers Combos >"{{ draw }}/base.yaml"
    yq -Yi '.combos.[].l = ["Combos"]' "{{ draw }}/base.yaml"
    keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/base.yaml" -z "sofle" >"{{ draw }}/base.svg"

clean:
    #!/usr/bin/env bash
    rm -rf ./build
    rm ./artifacts/* || true

build: clean
    #!/usr/bin/env bash
    num_targets=$(yq '.include | length' ./build.yaml)

    mkdir build
    mkdir artifacts

    venv zmk

    for i in $(seq 0 $((num_targets - 1))); do
        yq '.include['$i']' ./build.yaml

        name="$(yq -r '.include['$i'].["artifact-name"]' ./build.yaml)"
        build_dir="build/$name"
        board="$(yq -r '.include['$i'].board' ./build.yaml)"
        shield="$(yq -r '.include['$i'].shield' ./build.yaml)"
        config_dir="$(realpath ./config)"

        west build -s zmk/app -d "$build_dir" -b "$board" -- -DZMK_CONFIG="$config_dir" -DSHIELD="$shield" || exit 1

        mv "$build_dir"/zephyr/zmk.uf2 ./artifacts/"$name".uf2
    done

flash:
    #!/usr/bin/env bash
    declare -A flashed
    declare -a targets

    for f in $(cd artifacts; ls sofle*); do
        name=${f%.*}
        targets=(${targets[@]} $name)
        flashed["$name"]=0
        flashed["${name}_id"]="$(yq -r '.include[] | select(.["artifact-name"] == "'$name'") | .id' ./build.yaml)"
    done

    for target in "${targets[@]}"; do
        echo "Waiting for disk ID:${flashed[${target}_id]} for target:$target"
    done

    while (( ${#targets[@]} != 0 )); do
        for target in "${targets[@]}"; do
            media_dir="/media/$USER/$target"

            num_entries=$(ls /dev/disk/by-id/*${flashed[${target}_id]}* 2> /dev/null | wc -l)

            if [[ 1 -lt $num_entries ]]; then
                echo "Too many media for target:$target found"

                ls /dev/disk/by-id/*${flashed[${target}_id]}*

                for i in "${!targets[@]}"; do
                    if [[ ${targets[i]} = $target ]]; then
                        unset targets[$i]
                    fi
                done

                continue
            elif [[ 0 -eq $num_entries ]]; then
                sleep 0.5
                continue
            fi

            echo "Media ${flashed[${target}_id]} for target:$target found"

            sudo mkdir -p "$media_dir"
            sudo mount "$(ls /dev/disk/by-id/*${flashed[${target}_id]}*)" "$media_dir"
            sudo cp "artifacts/${target}.uf2" "$media_dir/$target.uf2"
            sudo umount "$media_dir"

            for i in "${!targets[@]}"; do
                if [[ ${targets[i]} = $target ]]; then
                    unset targets[$i]
                fi
            done
        done
        sleep 2
    done
