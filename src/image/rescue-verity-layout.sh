#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pure inner-container geometry; physical GPT/liblp allocations are unchanged.
rescue_verity_hash_blocks() {
    local blocks=$1 total=0
    [[ $blocks =~ ^[1-9][0-9]{0,9}$ ]] && ((blocks <= 536870912)) || return 2
    while ((blocks > 1)); do
        blocks=$(((blocks + 127) / 128))
        total=$((total + blocks))
    done
    printf '%s\n' "$total"
}
rescue_verity_layout() {
    local bytes=$1 low=1 high middle tree best=0 blocks padding
    [[ $bytes =~ ^[1-9][0-9]{0,12}$ ]] || return 2
    ((bytes <= 2199023255552 && bytes % 4096 == 0)) || return 2
    blocks=$((bytes / 4096))
    high=$blocks
    while ((low <= high)); do
        middle=$(((low + high) / 2))
        tree=$(rescue_verity_hash_blocks "$middle")
        if ((middle + tree <= blocks)); then
            best=$middle; low=$((middle + 1))
        else
            high=$((middle - 1))
        fi
    done
    ((best >= 4096)) || return 2
    tree=$(rescue_verity_hash_blocks "$best")
    padding=$((bytes - (best + tree) * 4096))
    jq -n --argjson bytes "$bytes" --argjson blocks "$best" --argjson tree "$tree" --argjson padding "$padding" \
        '{schema_version:1,container_bytes:$bytes,data_blocks:$blocks,data_bytes:($blocks*4096),
          hash_offset_bytes:($blocks*4096),hash_blocks:$tree,hash_bytes:($tree*4096),
          tail_padding_bytes:$padding,data_block_size:4096,hash_block_size:4096,
          format:1,hash:"sha256",superblock:false,filesystem:"ext4",read_only:true,
          partition_table_changes:false,liblp_allocation_changes:false,
          geometry_is_authentication:false}'
}
