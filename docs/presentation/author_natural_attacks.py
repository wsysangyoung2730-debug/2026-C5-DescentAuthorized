"""Author anticipation, weapon action, follow-through, and recovery for 21 actors.

Run with the repository's USD Python. Only attack/heavyAttack animation samples
and their manifest timing/socket metadata are changed. Existing geometry, skins,
idle, telegraph, hit, and fracture/death clips are retained. Angles below are
degrees about the actor's rest-space axes, not raw joint-local Euler angles.
"""
from pathlib import Path
import argparse
import json
from pxr import Gf, Usd, UsdSkel, Vt

ROOT = Path(__file__).resolve().parents[2]
ACTORS = ROOT / "DescentAuthorized/Resources/Reality/Actors"


def track(wind, release, follow):
    return {"wind": wind, "release": release, "follow": follow}


# Every action was selected from the actual actor silhouette and held prop.
# Armored forearms/wrists stay rigid; the shoulder drives their complete tools.
PROFILES = {
    "RecordAdministrator": {
        "action": "draw the sword back, diagonal forward cut, shield held in guard",
        "side": "R", "socket": "upper_arm_R", "tip": [-.83, -.35, .58],
        "joints": {
            "upper_arm_R": track([15, -9, -16], [-32, -18, 28], [-39, -12, 38]),
            "upper_arm_L": track([-3, 4, 0], [-9, 7, -3], [-7, 5, -2]),
            "spine": track([-1.8, 0, -2.2], [2.2, 0, 2.6], [1.2, 0, 3.2]),
            "head": track([0, 0, 2], [-1, 0, -2], [0, 0, -1]),
        },
    },
    "ObservationAdministrator": {
        "action": "raise and hold the arm cannon on target, fire, absorb recoil, lower",
        "side": "R", "socket": "upper_arm_R", "tip": [-.83, -.39, 1.12],
        "joints": {
            "upper_arm_R": track([-35, 0, -5], [-44, 0, 0], [-29, 1, -2]),
            "upper_arm_L": track([-6, 6, 3], [-10, 8, 4], [-7, 6, 3]),
            "spine": track([1, 0, 0], [1, 0, 0], [-2.2, 0, 0]),
            "head": track([-2, 0, 0], [-2, 0, 0], [1, 0, 0]),
        },
    },
    "ObservationResidue": {
        "action": "open paired claws, sweep the right claw across, left claw follows",
        "side": "R", "socket": "upper_arm_R", "tip": [-.73, -.38, .96],
        "joints": {
            "upper_arm_R": track([-11, -20, -18], [-36, 12, 18], [-26, 22, 30]),
            "upper_arm_L": track([-7, 16, 16], [-18, -8, -13], [-30, -18, -24]),
            "spine": track([0, 0, -1.5], [1, 0, 2], [1, 0, 2.5]),
        },
    },
    "CoordinateResidue": {
        "action": "brace the left tool, draw right coordinate spear, thrust and retract",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([13, -8, -9], [-42, -5, 10], [-48, -3, 14]),
            "upper_arm_L": track([-3, 3, 4], [-10, 3, 3], [-7, 2, 3]),
            "chest": track([-1.5, 0, -2], [2, 0, 2.5], [1.5, 0, 3]),
        },
    },
    "CoordinateAdministrator": {
        "action": "ground the staff and halo, raise free left instrument, issue an outward decree",
        "side": "L", "socket": "upper_arm_L", "fixedSupport": "R",
        "joints": {
            "upper_arm_L": track([-9, -12, 11], [-31, 13, -13], [-26, 20, -22]),
            "head": track([-2, 0, 3], [1, 0, -3], [0, 0, -2]),
        },
    },
    "CausalityResidue": {
        "action": "hold the rear clock frame steady, suspend the front right hand, delayed sharp strike",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([-18, -7, -12], [-39, 8, 16], [-28, 14, 24]),
            "upper_arm_L": track([-3, 2, 3], [-7, 3, -3], [-4, 2, -2]),
        },
    },
    "CausalityAdministrator": {
        "action": "keep the open ledger supported, lift the right quill, inscribe then flick forward",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([-13, -8, -12], [-29, 6, 11], [-18, 12, 24]),
            "head": track([3, 0, -3], [-1, 0, 2], [0, 0, 2]),
        },
    },
    "MemoryOmissionResidue": {
        "action": "spread the heavy claws, rake inward with the right arm, finish with left claw",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([9, -19, -13], [-27, 15, 19], [-22, 23, 25]),
            "upper_arm_L": track([5, 15, 10], [-13, -10, -11], [-24, -19, -19]),
            "chest": track([-1, 0, -1.5], [2, 0, 1.5], [1, 0, 2.5]),
        },
    },
    "OriginalMemoryAdministrator": {
        "action": "raise the complete memory stamp in the right hand, press forward, settle its weight",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([-16, -6, -8], [-32, 6, 10], [-20, 10, 14]),
            "head": track([2, 0, -2], [-1, 0, 2], [0, 0, 1]),
        },
    },
    "SignatureMimicResidual": {
        "action": "support the book with left hand, draw a right-hand signature arc and flick it out",
        "side": "R", "socket": "hand_R",
        "joints": {
            "upper_arm_R": track([-7, -9, -11], [-20, 5, 13], [-12, 10, 24]),
            "forearm_R": track([7, 0, -5], [-9, 0, 7], [-5, 0, 12]),
            "hand_R": track([0, -4, -5], [0, 6, 7], [0, 2, 11]),
            "head": track([3, 0, -3], [-1, 0, 2], [0, 0, 2]),
        },
    },
    "RejectionExecutionResidual": {
        "action": "lift the entire right stamp assembly, drive it down and forward, shield stays braced",
        "side": "R", "socket": "upper_arm_R", "tip": [-1.04, -.38, 1.00],
        "joints": {
            "upper_arm_R": track([-34, -5, -8], [-18, 0, 7], [3, 3, 10]),
            "upper_arm_L": track([-3, 3, 1], [-8, 6, 0], [-7, 4, 0]),
            "head": track([-2, 0, 0], [2, 0, 0], [1, 0, 0]),
        },
    },
    "ResponsibilityAuditAdministrator": {
        "action": "hold the grounded right staff and scales, cock the left seal and punch its face forward",
        "side": "L", "socket": "upper_arm_L", "fixedSupport": "R",
        "joints": {
            "upper_arm_L": track([8, 5, 10], [-28, -8, -10], [-33, -6, -14]),
            "head": track([-1, 0, 2], [1, 0, -2], [0, 0, -1]),
        },
    },
    "ConsentCustodianResidual": {
        "action": "present the held book with both hands together, recoil its weight, lower together",
        "side": "R", "socket": "equipment_book",
        "joints": {
            "chest": track([-3.8, 0, 0], [5.8, 0, 0], [4.0, 0, 0]),
            "head": track([5, 0, 0], [-3, 0, 0], [-1, 0, 0]),
        },
    },
    "QuarantineEnforcerResidual": {
        "action": "open the two rigid pincers, right clamp reaches then left clamp closes the space",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([6, -15, -13], [-37, 9, 13], [-31, 16, 21]),
            "upper_arm_L": track([4, 12, 10], [-22, -7, -8], [-31, -14, -18]),
        },
    },
    "VoluntaryQuarantineAdministrator": {
        "action": "draw the open right palm toward the chest, turn and extend it to command isolation",
        "side": "R", "socket": "hand_R",
        "joints": {
            "upper_arm_R": track([14, -7, -10], [-24, 9, 12], [-29, 13, 17]),
            "forearm_R": track([12, 0, -4], [-13, 0, 5], [-8, 0, 8]),
            "hand_R": track([0, -7, 0], [0, 8, 4], [0, 4, 7]),
            "head": track([-2, 0, -3], [1, 0, 2], [0, 0, 2]),
        },
    },
    "OverloadResidual": {
        "action": "wind up the pressurized right clamp, snap it forward, absorb the pressure kick",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([13, -7, -13], [-35, 6, 10], [-24, 11, 18]),
            "upper_arm_L": track([-4, 4, 5], [-12, -3, -4], [-7, -2, -3]),
            "head": track([-2, 0, 0], [1, 0, 0], [-1, 0, 0]),
        },
    },
    "BackflowBlockerResidual": {
        "action": "brace the round shield, swing the right hook from outside inward, let it follow through",
        "side": "R", "socket": "upper_arm_R",
        "joints": {
            "upper_arm_R": track([5, -16, -19], [-31, 9, 18], [-25, 17, 29]),
            "upper_arm_L": track([-4, 4, 2], [-10, 7, -2], [-8, 5, -1]),
        },
    },
    "SealMaintenanceAdministrator": {
        "action": "anchor right staff and rear tanks, draw the left claw inward then release a pressure push",
        "side": "L", "socket": "upper_arm_L", "fixedSupport": "R",
        "joints": {
            "upper_arm_L": track([10, 7, 9], [-29, -7, -10], [-35, -10, -16]),
            "head": track([-1, 0, 2], [1, 0, -2], [0, 0, -1]),
        },
    },
    "IdentityComparisonResidual": {
        "action": "keep the identity ledger supported, trace a short scan with the raised pointer and point outward",
        "side": "R", "socket": "hand_R",
        "joints": {
            "upper_arm_R": track([-5, -8, -9], [-19, 7, 12], [-14, 11, 19]),
            "forearm_R": track([6, 0, -4], [-8, 0, 5], [-4, 0, 8]),
            "hand_R": track([0, -3, -3], [0, 4, 4], [0, 2, 6]),
            "head": track([1, 0, -4], [-1, 0, 3], [0, 0, 2]),
        },
    },
    "ExitReviewResidual": {
        "action": "brace the tower shield, raise the right baton, deliver a diagonal downward judgement",
        "side": "R", "socket": "upper_arm_R", "tip": [-.71, -.25, .57],
        "joints": {
            "upper_arm_R": track([-31, -10, -15], [-20, 10, 17], [1, 16, 25]),
            "upper_arm_L": track([-3, 3, 0], [-8, 4, -2], [-6, 3, -1]),
        },
    },
    "FinalAuthorizationAdministrator": {
        "action": "keep left authority staff grounded, gather with right palm then deliver an outward decree",
        "side": "R", "socket": "upper_arm_R", "fixedSupport": "L",
        "joints": {
            "upper_arm_R": track([9, -9, -10], [-28, 11, 12], [-32, 16, 21]),
            "head": track([-1, 0, -2], [1, 0, 2], [0, 0, 1]),
        },
    },
}


def resolve(names, semantic):
    variants = [semantic]
    if semantic.startswith("upper_arm_"):
        variants.append(semantic.replace("upper_arm_", "arm_"))
    mix = {"spine": "Spine", "chest": "Spine2", "head": "Head",
           "upper_arm_L": "LeftArm", "upper_arm_R": "RightArm",
           "forearm_L": "LeftForeArm", "forearm_R": "RightForeArm",
           "hand_L": "LeftHand", "hand_R": "RightHand"}
    if semantic in mix:
        variants.append("mixamorig_" + mix[semantic])
    return next((i for i, j in enumerate(names) if j.split("/")[-1] in variants), None)


def smooth(value):
    v = max(0, min(1, value))
    return v * v * (3 - 2 * v)


def angles_at(seconds, data, heavy):
    release, end = (.54, 1.28) if heavy else (.40, .96)
    wind_time, hold_time = (.30, .43) if heavy else (.21, .30)
    follow_time = .69 if heavy else .52
    settle_time = 1.04 if heavy else .79
    # Recovery overshoots only a few percent; the weapon never snaps to idle.
    power = 1.10 if heavy else 1.0
    keys = [(0., (0, 0, 0)), (wind_time, data["wind"]), (hold_time, data["wind"]),
            (release, data["release"]), (follow_time, data["follow"]),
            (settle_time, tuple(-v * .035 for v in data["wind"])), (end, (0, 0, 0))]
    if seconds >= end:
        return (0, 0, 0)
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if ta <= seconds <= tb:
            u = smooth((seconds - ta) / (tb - ta))
            return tuple((x + (y - x) * u) * power for x, y in zip(a, b))
    return (0, 0, 0)


def write_actor(name):
    folder = ACTORS / name
    manifest_path = folder / "motion.json"
    manifest = json.loads(manifest_path.read_text())
    stage = Usd.Stage.Open(str(folder / "articulated.usdc"))
    skeleton = next(UsdSkel.Skeleton(p) for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
    animation = next(UsdSkel.Animation(p) for p in stage.Traverse() if p.IsA(UsdSkel.Animation))
    names = list(skeleton.GetJointsAttr().Get())
    assert list(animation.GetJointsAttr().Get()) == names
    rests = skeleton.GetRestTransformsAttr().Get()
    binds = skeleton.GetBindTransformsAttr().Get()
    rotations = animation.GetRotationsAttr()
    translations = animation.GetTranslationsAttr()
    scales = animation.GetScalesAttr()
    profile = PROFILES[name]
    base_q = [Gf.Quatd(m.ExtractRotationQuat()) for m in rests]
    bases = [Gf.Quatd(m.ExtractRotationQuat()) for m in binds]
    # Imported Mixamo actor has a different rest-space heading; derive its own axes.
    li, ri = resolve(names, "upper_arm_L"), resolve(names, "upper_arm_R")
    lateral = binds[li].ExtractTranslation() - binds[ri].ExtractTranslation()
    lateral[2] = 0
    lateral.Normalize()
    back = Gf.Vec3d(-lateral[1], lateral[0], 0)
    axes = [lateral, back, Gf.Vec3d(0, 0, 1)]
    joint_tracks = {resolve(names, semantic): values for semantic, values in profile["joints"].items()}
    assert None not in joint_tracks, (name, profile["joints"])
    fps = stage.GetTimeCodesPerSecond()
    report = {"actor": name, "action": profile["action"], "clips": {},
              "movingJoints": [names[i] for i in joint_tracks], "fixedSupport": profile.get("fixedSupport")}
    for clip_name in ["attack", "heavyAttack"]:
        clip = manifest["clips"][clip_name]
        heavy = clip_name == "heavyAttack"
        start, finish = round(clip["start"] * fps), round(clip["end"] * fps)
        start_translations = translations.Get(start)
        start_scales = scales.Get(start)
        # Preserve bind/pose scale and translation; no foot slide or model-level lunge.
        for frame in range(start, finish + 1):
            seconds = (frame - start) / fps
            quats = list(base_q)
            for i, values in joint_tracks.items():
                angle = angles_at(seconds, values, heavy)
                delta = Gf.Quatd(1)
                for axis, degrees in zip(axes, angle):
                    delta = delta * Gf.Rotation(axis, degrees).GetQuat()
                quats[i] = base_q[i] * bases[i].GetInverse() * delta * bases[i]
            rotations.Set(Vt.QuatfArray([Gf.Quatf(q.GetNormalized()) for q in quats]), frame)
            if start_translations is not None:
                translations.Set(start_translations, frame)
            if start_scales is not None:
                scales.Set(start_scales, frame)
        clip.update(release=.54 if heavy else .40, impact=.62 if heavy else .46,
                    settledAt=1.28 if heavy else .96)
        report["clips"][clip_name] = dict(clip, authoredFrames=finish - start + 1)
    socket_i = resolve(names, profile["socket"])
    assert socket_i is not None
    if "tip" in profile:
        position = Gf.Vec3d(*profile["tip"])
    else:
        hand_i = resolve(names, "hand_" + profile["side"])
        position = binds[hand_i if hand_i is not None else socket_i].ExtractTranslation() - back * .12
    offset = binds[socket_i].GetInverse().Transform(position)
    manifest["attackSocket"] = {"joint": names[socket_i], "offset": [round(float(x), 6) for x in offset]}
    manifest["attackMotion"] = {"version": 2, "action": profile["action"], "groundedRoot": True,
                                "phases": ["anticipation", "aim-or-arc", "release", "followThrough", "settle"]}
    manifest["runtimeMotion"] = "authoredArticulated"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    stage.GetRootLayer().Save()
    report["attackSocket"] = manifest["attackSocket"]
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    names = args.only or sorted(PROFILES)
    rows = []
    for name in names:
        rows.append(write_actor(name))
        print(name, flush=True)
    (ROOT / "docs/presentation/natural-attack-authoring.json").write_text(
        json.dumps({"version": 2, "actors": rows}, ensure_ascii=False, indent=2) + "\n")
