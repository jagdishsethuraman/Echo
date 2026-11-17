#!/usr/bin/env python3
import os
import struct

def pack_icns(iconset_dir, output_icns_path):
    mapping = {
        "icp4": "icon_16x16.png",
        "ic11": "icon_16x16@2x.png",
        "icp5": "icon_32x32.png",
        "ic12": "icon_32x32@2x.png",
        "ic07": "icon_128x128.png",
        "ic13": "icon_128x128@2x.png",
        "ic08": "icon_256x256.png",
        "ic14": "icon_256x256@2x.png",
        "ic09": "icon_512x512.png",
        "ic10": "icon_512x512@2x.png",
    }
    
    chunks = []
    for tag, filename in mapping.items():
        filepath = os.path.join(iconset_dir, filename)
        if os.path.exists(filepath):
            with open(filepath, "rb") as f:
                png_bytes = f.read()
            chunk_len = len(png_bytes) + 8
            chunk_header = tag.encode("latin1") + struct.pack(">I", chunk_len)
            chunks.append(chunk_header + png_bytes)
            print(f"Packaged {tag} ({filename}): {len(png_bytes)} bytes")
            
    payload = b"".join(chunks)
    total_len = len(payload) + 8
    header = b"icns" + struct.pack(">I", total_len)
    
    with open(output_icns_path, "wb") as f:
        f.write(header + payload)
        
    print(f"Successfully generated {output_icns_path} ({total_len} bytes)")

if __name__ == "__main__":
    iconset = "/Users/ragavij/Documents/Developer/Echo/Echo.iconset"
    out_icns = "/Users/ragavij/Documents/Developer/Echo/AppIcon.icns"
    pack_icns(iconset, out_icns)
