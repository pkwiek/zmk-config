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
