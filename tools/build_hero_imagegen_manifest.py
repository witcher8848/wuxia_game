#!/usr/bin/env python3
"""Reproducible hero metadata and byte-identical original-PNG staging.

--emit measures source regions read-only and prints JSON (bundled Pillow needed).
--copy-originals copies files without pixel processing or overwriting differences.
--verify is stdlib-only: validates the saved 57-slot manifest, source parity and
original-alpha import settings. It never repairs an asset or edits an image.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from validate_hero_manifest import validate_manifest, read_png_info

MANIFEST = "assets/runtime/characters/chr_protagonist_imagegen_20261012.json"
RAW_DIRECTORY = "assets/runtime/characters/imagegen_20261012"
DIRECTIONS = ("down", "left", "right", "up")
# key: filename, columns, rows, shared nominal standing/body source height.
SOURCES = {
    "walk_down": ("hero_walk_down_20261012.png",4,1,836),
    "walk_down_legacy": ("protagonist_imagegen_walk_down_sheet_20261011.png",4,1,836),
    "walk_left": ("protagonist_imagegen_walk_left_sheet_20261011_v2.png",4,1,805),
    "walk_right": ("hero_walk_right_20261012.png",4,1,805),
    "walk_up": ("hero_walk_up_20261012.png",4,1,815),
    "left_contact2": ("hero_walk_left_contact2_20261012_v2.png",1,1,0),
    "right_contact2": ("hero_walk_right_contact2_20261012.png",1,1,0),
    "front_first": ("hero_front_fist_thrust_20261012.png",4,1,695),
    "front_extra": ("hero_front_windup_guard_20261012.png",2,1,772),
    "combat_down": ("protagonist_imagegen_combat_down_sheet_20261011.png",2,4,375),
    "left_extra": ("hero_left_thrust_windup_20261012.png",2,1,650),
    "combat_left": ("protagonist_imagegen_combat_left_sheet_20261011.png",2,4,360),
    "combat_right": ("protagonist_imagegen_combat_right_sheet_20261011_v3.png",2,4,372),
    "combat_up": ("protagonist_imagegen_combat_up_sheet_20261011.png",2,4,351),
    "defeat": ("protagonist_imagegen_defeat_20261011.png",1,1,840),
}
IMPORT_VALUES = {
    "compress/mode":"0","mipmaps/generate":"false","process/fix_alpha_border":"false",
    "process/premult_alpha":"false","process/size_limit":"0",
    "process/channel_remap/red":"0","process/channel_remap/green":"1",
    "process/channel_remap/blue":"2","process/channel_remap/alpha":"3",
}
# Reviewed body-axis X positions in original source coordinates. A single
# grounded shoe alternates left/right: anchoring X to that shoe would make the
# whole torso sway by ~10 display pixels. Y still follows the reviewed floor.
# These change metadata only; every original PNG remains byte-identical.
BODY_AXIS_X = {
    "walk_down": (248,672,1107,1544),
    "walk_down_legacy": (248,672,1107,1544),
    "walk_left": (230,663,1100,1537),
    "walk_right": (245,673,1105,1544),
    "walk_up": (227,678,1110,1548),
    "left_contact2": (500,),
    "right_contact2": (530,),
    "defeat": (889,),
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def reference_path(root, relative):
    if not isinstance(relative,str) or not relative.startswith("docs/art_reference/"):
        raise ValueError("source_reference must be under docs/art_reference")
    if "\\" in relative or any(p in ("","..",".") for p in relative.split("/")):
        raise ValueError("noncanonical source_reference")
    path = (root/relative).resolve()
    if not path.is_relative_to((root/"docs/art_reference").resolve()) or path.suffix != ".png":
        raise ValueError("source_reference escapes original directory")
    if not path.is_file(): raise ValueError("original PNG is missing: "+relative)
    return path

def measure_sources(root):
    # Local read-only analyzer; no crop/resize/save, no PNG masks exported.
    from analyze_hero_source_regions import analyze
    from PIL import Image
    cache = {}
    for key,(filename,columns,rows,body_height) in SOURCES.items():
        path = root/"docs/art_reference"/filename
        result = analyze(path,key,columns,rows)
        with Image.open(path) as picture:
            picture.load()
            alpha = picture.getchannel("A")
            for slot in result["slots"]:
                if slot.get("recommended_gpu_region_xywh") is None: continue
                x0,y0,x1,y1 = slot["bounds_exclusive"]
                # Sole-plane midpoint, not the weapon-inclusive rectangle center.
                xs = [x for y in range(max(y0,y1-8),y1)
                      for x in range(x0,x1) if alpha.getpixel((x,y))>127]
                slot["anchor_source"] = [(min(xs)+max(xs)+1)/2 if xs else (x0+x1)/2,y1]
                if key in BODY_AXIS_X:
                    slot["anchor_source"][0] = BODY_AXIS_X[key][slot["index"]]
        result["source_reference"] = "docs/art_reference/"+filename
        nominal_height = body_height or max(slot["bounds_exclusive"][3]-slot["bounds_exclusive"][1] for slot in result["slots"])
        result["scale"] = 68.0/nominal_height
        cache[key] = result
    return cache

def make_manifest(root):
    cache = measure_sources(root)
    frames,clips = [],{}
    def add(key,index,name):
        image = cache[key]
        slot = image["slots"][index]
        if not slot.get("rectangular_subject_isolation") or slot.get("recommended_gpu_region_xywh") is None:
            raise ValueError(f"unsafe/non-independent source frame: {key} {index}")
        region = slot["recommended_gpu_region_xywh"]
        scale = image["scale"]
        if key=="defeat":
            # Lying body's length uses the same approximate physical head scale
            # as the reference, not a 68px-tall stretched corpse.
            scale=68.0/840
        size=[region[2]*scale,region[3]*scale]
        foot=slot["anchor_source"]
        anchor=[round((foot[0]-region[0])*scale),round((foot[1]-region[1])*scale)]
        anchor=[min(size[n],max(0,anchor[n])) for n in (0,1)]
        record={"id":name,"texture":"res://"+RAW_DIRECTORY+"/"+Path(image["source_reference"]).name,
                "region":region,"display_size":size,"anchor":anchor,
                "source_sha256":image["sha256"],"source_reference":image["source_reference"],
                "source_size":image["size"],"anchor_source":foot,
                "source_pose_index":index}
        frames.append(record)
        return len(frames)-1
    for direction in DIRECTIONS:
        walk=[]
        for phase in range(4):
            key,index="walk_"+direction,phase
            if direction=="down" and phase<3:
                # The passing-pose correction regressed its third figure.
                # Keep the proven original contacts; use only its corrected 3.
                key="walk_down_legacy"
            elif direction in ("left","right") and phase==2:
                key,index=direction+"_contact2",0
            walk.append(add(key,index,f"walk_{direction}_{phase}"))
        clips["walk_"+direction]={"cells":walk,"fps":8,"loop":True}
        clips["idle_"+direction]={"cells":[walk[0]],"fps":1,"loop":True}
        if direction=="down":
            poses=[("front_first",i) for i in range(4)]
            poses += [("front_extra",0),("combat_down",5),("front_extra",1),("combat_down",7)]
        elif direction=="left":
            poses=[("combat_left",0),("combat_left",1),("left_extra",0),("combat_left",3),
                   ("left_extra",1),("combat_left",5),("combat_left",6),("combat_left",7)]
        else: poses=[("combat_"+direction,i) for i in range(8)]
        for action,indices,fps in (("strike",[0,1],10),("thrust",[2,3,None],10),
                                   ("slash",[4,5,None],10),("guard",[6],3),("hit",[7],5)):
            cells=[]
            for phase,index in enumerate(indices):
                if index is None:
                    record=dict(frames[walk[0]],id=f"{action}_{direction}_{phase}",
                                recovery_reuses=f"walk_{direction}_0")
                    frames.append(record)
                    cells.append(len(frames)-1)
                else:
                    key,source_index=poses[index]
                    cells.append(add(key,source_index,f"{action}_{direction}_{phase}"))
            clips[action+"_"+direction]={"cells":cells,"fps":fps,"loop":False}
    down=add("defeat",0,"down")
    clips["down"]={"cells":[down],"fps":1,"loop":False}
    return {"schema_version":2,"frame_count":57,"nominal_display_size":[48,72],
            "contract":"imagegen originals; original alpha; GPU regions; physics unchanged",
            "frames":frames,"clips":clips}

def load_manifest(root):
    return json.loads((root/MANIFEST).read_text(encoding="utf-8"))

def copy_originals(root,manifest):
    for record in manifest["frames"]:
        source=reference_path(root,record["source_reference"])
        relative=record["texture"].removeprefix("res://")
        if not relative.startswith(RAW_DIRECTORY+"/") or Path(relative).name!=source.name:
            raise ValueError("runtime destination must be the original filename in imagegen directory")
        destination=root/relative
        if digest(source)!=record["source_sha256"]: raise ValueError("source SHA mismatch")
        destination.parent.mkdir(parents=True,exist_ok=True)
        if destination.exists():
            if not destination.is_file() or digest(destination)!=digest(source):
                raise ValueError("refusing to overwrite different existing original PNG")
        else: shutil.copyfile(source,destination)
    print("HERO_ORIGINAL_COPY_PASS byte-identical files only; no PNG pixel processing")

def verify(root):
    manifest=load_manifest(root)
    errors=validate_manifest(manifest,root)
    if errors: raise ValueError("\n".join(errors))
    checked=set()
    for record in manifest["frames"]:
        source=reference_path(root,record.get("source_reference"))
        runtime=root/record["texture"].removeprefix("res://")
        if digest(source)!=digest(runtime) or digest(source)!=record["source_sha256"]:
            raise ValueError("original/runtime SHA parity failed")
        info=read_png_info(source)
        if record.get("source_size") != [info.width,info.height]:
            raise ValueError("source_size differs from original IHDR")
        if runtime in checked: continue
        checked.add(runtime)
        config=Path(str(runtime)+".import")
        params={}
        section=""
        for line in config.read_text(encoding="utf-8").splitlines():
            if line.startswith("["): section=line
            elif section=="[params]" and "=" in line:
                key,value=line.split("=",1); params[key.strip()]=value.strip()
        for key,value in IMPORT_VALUES.items():
            if params.get(key)!=value: raise ValueError(f"{runtime.name}: {key} must be {value}")
    print(f"HERO_IMAGEGEN_MANIFEST_PASS frames=57 originals={len(checked)}; source parity/import/structure, NOT animation naturalness")
    return 0

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root",type=Path,default=Path(__file__).resolve().parents[1])
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--emit",action="store_true")
    group.add_argument("--copy-originals",action="store_true")
    group.add_argument("--verify",action="store_true")
    args=parser.parse_args()
    root=args.project_root.resolve()
    try:
        if args.emit: print(json.dumps(make_manifest(root),ensure_ascii=False,separators=(",",":")))
        elif args.copy_originals: copy_originals(root,load_manifest(root))
        else: return verify(root)
    except (OSError,ValueError,KeyError,IndexError) as error:
        print("HERO_IMAGEGEN_MANIFEST_FAIL "+str(error),file=sys.stderr)
        return 1
    return 0

if __name__=="__main__": raise SystemExit(main())
