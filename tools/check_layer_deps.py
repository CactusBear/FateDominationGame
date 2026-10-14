#!/usr/bin/env python
"""Read-only A04/A05 ratchet. No capture/update mode: remove retired entries only.

Exact lexical code anchors + counted occurrences avoid broad file/member waivers.
Whitespace, comments and line-number changes do not affect anchors. Scan all *.gd
outside .git/.godot; layer restrictions apply only to the plan's named directories.
This is a static lexical gate, not a GDScript compiler or dynamic alias analysis.
"""
from __future__ import annotations

import argparse
import json
from bisect import bisect_right
from collections import Counter
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import re
import sys

LAYER_ROOTS = ("scripts/system/", "scripts/match/") + tuple(
    f"scripts/net/{part}/" for part in
    ("authority", "session", "server", "content", "validation", "transport", "identity")
)
UI_ROOTS = ("scripts/game_scene/", "scripts/net/ui/", "assets/scenes/")
OWNERS = {
    "EffectManager": "scripts/system/global/effect_manager.gd",
    "GameProgress": "scripts/system/global/game_progress.gd",
    "DummyBot": "scripts/system/ai/rule_bot.gd",
}
# Godot 4.7.2.stable.official.ed1daf0bf ClassDB Node descendants.
# Refresh this type inventory when upgrading the engine (not the exception list).
NODE_BASES = frozenset((
    'AcceptDialog AimModifier3D AnimatableBody2D AnimatableBody3D AnimatedSprite2D '
    'AnimatedSprite3D AnimationMixer AnimationPlayer AnimationTree Area2D '
    'Area3D AreaLight3D AspectRatioContainer AudioListener2D AudioListener3D '
    'AudioStreamPlayer AudioStreamPlayer2D AudioStreamPlayer3D BackBufferCopy BaseButton '
    'Bone2D BoneAttachment3D BoneConstraint3D BoneTwistDisperser3D BoxContainer '
    'Button CCDIK3D CPUParticles2D CPUParticles3D CSGBox3D '
    'CSGCombiner3D CSGCylinder3D CSGMesh3D CSGPolygon3D CSGPrimitive3D '
    'CSGShape3D CSGSphere3D CSGTorus3D Camera2D Camera3D '
    'CanvasGroup CanvasItem CanvasLayer CanvasModulate CenterContainer '
    'ChainIK3D CharacterBody2D CharacterBody3D CheckBox CheckButton '
    'CodeEdit CollisionObject2D CollisionObject3D CollisionPolygon2D CollisionPolygon3D '
    'CollisionShape2D CollisionShape3D ColorPicker ColorPickerButton ColorRect '
    'ConeTwistJoint3D ConfirmationDialog Container Control ConvertTransformModifier3D '
    'CopyTransformModifier3D DampedSpringJoint2D Decal DirectionalLight2D DirectionalLight3D '
    'EditorAbout EditorAssetLibrary EditorCommandPalette EditorDock EditorFileDialog '
    'EditorFileSystem EditorInspector EditorPlugin EditorProperty EditorResourcePicker '
    'EditorResourcePreview EditorScriptPicker EditorSpinSlider EditorTitleBar EditorToaster '
    'EditorVersionButton EngineUpdateLabel FABRIK3D FileDialog FileSystemDock '
    'FlowContainer FogVolume FoldableContainer GPUParticles2D GPUParticles3D '
    'GPUParticlesAttractor3D GPUParticlesAttractorBox3D GPUParticlesAttractorSphere3D GPUParticlesAttractorVectorField3D GPUParticlesCollision3D '
    'GPUParticlesCollisionBox3D GPUParticlesCollisionHeightField3D GPUParticlesCollisionSDF3D GPUParticlesCollisionSphere3D Generic6DOFJoint3D '
    'GeometryInstance3D GraphEdit GraphElement GraphFrame GraphNode '
    'GridContainer GridMap GridMapEditorPlugin GrooveJoint2D HBoxContainer '
    'HFlowContainer HScrollBar HSeparator HSlider HSplitContainer '
    'HTTPRequest HingeJoint3D IKModifier3D ImporterMeshInstance3D InstancePlaceholder '
    'ItemList IterateIK3D JacobianIK3D Joint2D Joint3D '
    'Label Label3D Light2D Light3D LightOccluder2D '
    'LightmapGI LightmapProbe LimitAngularVelocityModifier3D Line2D LineEdit '
    'LinkButton LookAtModifier3D MarginContainer Marker2D Marker3D '
    'MenuBar MenuButton MeshInstance2D MeshInstance3D MissingNode '
    'ModifierBoneTarget3D MultiMeshInstance2D MultiMeshInstance3D MultiplayerSpawner MultiplayerSynchronizer '
    'NavigationAgent2D NavigationAgent3D NavigationLink2D NavigationLink3D NavigationObstacle2D '
    'NavigationObstacle3D NavigationRegion2D NavigationRegion3D NinePatchRect Node '
    'Node2D Node3D OccluderInstance3D OmniLight3D OpenXRBindingModifierEditor '
    'OpenXRCompositionLayer OpenXRCompositionLayerCylinder OpenXRCompositionLayerEquirect OpenXRCompositionLayerQuad OpenXRHand '
    'OpenXRInteractionProfileEditor OpenXRInteractionProfileEditorBase OpenXRRenderModel OpenXRRenderModelManager OpenXRVisibilityMask '
    'OptionButton Panel PanelContainer Parallax2D ParallaxBackground '
    'ParallaxLayer Path2D Path3D PathFollow2D PathFollow3D '
    'PhysicalBone2D PhysicalBone3D PhysicalBoneSimulator3D PhysicsBody2D PhysicsBody3D '
    'PinJoint2D PinJoint3D PointLight2D Polygon2D Popup '
    'PopupMenu PopupMenuItems PopupPanel ProgressBar ProgressDialog '
    'ProjectDialog ProjectList ProjectListItemControl ProjectManager QuickSettingsDialog '
    'Range RayCast2D RayCast3D ReferenceRect ReflectionProbe '
    'RemoteTransform2D RemoteTransform3D ResourcePreloader RetargetModifier3D RichTextLabel '
    'RigidBody2D RigidBody3D RootMotionView ScriptCreateDialog ScriptEditor '
    'ScriptEditorBase ScrollBar ScrollContainer Separator ShaderGlobalsOverride '
    'ShapeCast2D ShapeCast3D Skeleton2D Skeleton3D SkeletonIK3D '
    'SkeletonModifier3D Slider SliderJoint3D SoftBody3D SpinBox '
    'SplineIK3D SplitContainer SplitContainerDragger SpotLight3D SpringArm3D '
    'SpringBoneCollision3D SpringBoneCollisionCapsule3D SpringBoneCollisionPlane3D SpringBoneCollisionSphere3D SpringBoneSimulator3D '
    'Sprite2D Sprite3D SpriteBase3D StaticBody2D StaticBody3D '
    'StatusIndicator SubViewport SubViewportContainer TabBar TabContainer '
    'TextEdit TextureButton TextureProgressBar TextureRect TileMap '
    'TileMapLayer Timer TouchScreenButton Tree TwoBoneIK3D '
    'VBoxContainer VFlowContainer VScrollBar VSeparator VSlider '
    'VSplitContainer VehicleBody3D VehicleWheel3D VideoStreamPlayer Viewport '
    'VirtualJoystick VisibleOnScreenEnabler2D VisibleOnScreenEnabler3D VisibleOnScreenNotifier2D VisibleOnScreenNotifier3D '
    'VisualInstance3D VoxelGI Window WorldEnvironment XRAnchor3D '
    'XRBodyModifier3D XRCamera3D XRController3D XRFaceModifier3D XRHandModifier3D '
    'XRNode3D XROrigin3D '
).split())
TOKEN_RE = re.compile(
    r"(?P<comment>\#[^\n]*)|(?P<string>\"\"\"(?:\\.|(?!\"\"\").)*\"\"\"|"
    r"'''(?:\\.|(?!''').)*'''|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')|"
    r"(?P<id>[A-Za-z_][A-Za-z_0-9]*)|(?P<space>\s+)|(?P<punct>.)", re.DOTALL)


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    line: int


def lex(text: str) -> list[Token]:
    newlines = [m.start() for m in re.finditer("\n", text)]
    return [Token(m.lastgroup, m.group(), bisect_right(newlines, m.start()) + 1)
            for m in TOKEN_RE.finditer(text) if m.lastgroup not in {"comment", "space"}]


def literal(token: Token) -> str:
    width = 3 if token.value.startswith(('"""', "'''")) else 1
    return token.value[width:-width].replace('\\"', '"').replace("\\'", "'").replace('\\/', '/')


def resource_path(value: str) -> str:
    if not value.startswith("res://"):
        return ""
    parts: list[str] = []
    for part in PurePosixPath(value[6:]).parts:
        if part == "..":
            if parts:
                parts.pop()
        elif part != ".":
            parts.append(part)
    return "/".join(parts)


def signature(tokens: list[Token]) -> tuple:
    return tuple((token.kind, token.value) for token in tokens)


@dataclass(frozen=True)
class Finding:
    rule: str
    path: str
    line: int
    target: str
    anchor: tuple

    @property
    def key(self) -> tuple:
        return self.rule, self.path, self.target, self.anchor


@dataclass(frozen=True)
class ExceptionSite:
    rule: str
    path: str
    target: str
    code: str
    evidence_line: int

    @property
    def key(self) -> tuple:
        return self.rule, self.path, self.target, signature(lex(self.code))


# Evidence is frozen from the actual working tree, not the plan's estimates.
# Repeated entries are intentional: each is exactly one permitted occurrence.
ALLOWLIST = (


    ExceptionSite("layer", 'scripts/net/server/server_bootstrap.gd', 'res://assets/scenes/main_menu/server_console.tscn', '"--server-console":"res://assets/scenes/main_menu/server_console.tscn",', 76),
    ExceptionSite("layer", 'scripts/net/server/server_bootstrap.gd', 'res://assets/scenes/main_menu/server_room_worker.tscn', '"--server-room-worker":"res://assets/scenes/main_menu/server_room_worker.tscn",', 77),
    ExceptionSite("layer", 'scripts/net/server/server_bootstrap.gd', 'res://assets/scenes/main_menu/room_data_validation_worker.tscn', '"--room-data-validation-worker":"res://assets/scenes/main_menu/room_data_validation_worker.tscn",', 78),
    ExceptionSite("layer", 'scripts/net/server/server_bootstrap.gd', 'res://assets/scenes/main_menu/server_cli.tscn', '"--server-gateway":"res://assets/scenes/main_menu/server_cli.tscn"', 79),





















)


def collect_sources(root: Path) -> dict[str, list[Token]]:
    sources = {}
    for path in sorted(root.rglob("*.gd")):
        if any(part in {".git", ".godot"} for part in path.relative_to(root).parts):
            continue
        if not path.resolve(strict=True).is_relative_to(root.resolve(strict=True)):
            raise ValueError(f"source outside authorized root: {path}")
        if path.is_file():
            sources[path.relative_to(root).as_posix()] = lex(path.read_text(encoding="utf-8-sig"))
    return sources


def scan(root: Path) -> list[Finding]:
    sources = collect_sources(root)
    classes: dict[str, str] = {}
    parents: dict[str, Token] = {}
    for path, tokens in sources.items():
        for i, token in enumerate(tokens[:-1]):
            if token.kind == "id" and token.value == "class_name":
                classes[tokens[i + 1].value] = path
            if token.kind == "id" and token.value == "extends" and path not in parents:
                parents[path] = tokens[i + 1]

    def inherits_node(path: str, visited: frozenset = frozenset()) -> bool:
        if path in visited or path not in parents:
            return False
        parent = parents[path]
        if parent.kind == "id" and parent.value in NODE_BASES:
            return True
        target = resource_path(literal(parent)) if parent.kind == "string" else classes.get(parent.value, "")
        return inherits_node(target, visited | {path})

    findings: list[Finding] = []
    for path, tokens in sources.items():
        lines: dict[int, list[Token]] = {}
        for token in tokens:
            lines.setdefault(token.line, []).append(token)

        def add(rule: str, token: Token, target: str) -> None:
            findings.append(Finding(rule, path, token.line, target, signature(lines[token.line])))

        restricted = path.startswith(LAYER_ROOTS)
        text_module = path.startswith("scripts/ui/text/")
        for token in tokens:
            if token.kind == "string":
                target = resource_path(literal(token))
                if restricted and target.startswith(UI_ROOTS):
                    add("layer", token, "res://" + target)
                elif text_module and target.startswith("scripts/game_scene/"):
                    add("text-ui", token, "res://" + target)
            elif token.kind == "id" and token.value in classes:
                target = classes[token.value]
                if restricted and target.startswith(UI_ROOTS):
                    add("layer", token, token.value)
                elif text_module and target.startswith("scripts/game_scene/"):
                    add("text-ui", token, token.value)
        for i, token in enumerate(tokens[:-2]):
            member = tokens[i + 2]
            if (token.kind == "id" and token.value in OWNERS
                    and tokens[i + 1].value == "." and member.kind == "id"
                    and member.value.startswith("_") and path != OWNERS[token.value]):
                add("private", token, token.value + "." + member.value)
        if text_module and inherits_node(path):
            add("text-node", parents[path], "Node inheritance")
    return sorted(findings, key=lambda f: (f.path, f.line, f.rule, f.target))


def evaluate(findings: list[Finding], allowlist=ALLOWLIST) -> tuple[list[Finding], list[ExceptionSite]]:
    allowance = Counter(site.key for site in allowlist)
    new = []
    for finding in findings:
        if allowance[finding.key]:
            allowance[finding.key] -= 1
        else:
            new.append(finding)
    stale = []
    for site in allowlist:
        if allowance[site.key]:
            stale.append(site)
            allowance[site.key] -= 1
    return new, stale


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json", action="store_true", help="emit machine-readable verification")
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve(strict=True)
        if not (root / "scripts").is_dir():
            raise ValueError("缺少 scripts 目录，拒绝空扫描")
        findings = scan(root)
        new, stale = evaluate(findings)
    except (OSError, UnicodeError, ValueError) as exc:
        if args.json:
            print(json.dumps({"status": "ERROR", "exit_code": 2, "error": str(exc)}, ensure_ascii=False))
        else:
            print(f"ERROR {exc}", file=sys.stderr)
        return 2
    if args.json:
        def record(item):
            return {"rule": item.rule, "path": item.path, "line": getattr(item, "line", getattr(item, "evidence_line", 0)), "target": item.target}
        code = int(bool(new or stale))
        print(json.dumps({"status": "FAIL" if code else "PASS", "exit_code": code,
                          "root": root.as_posix(), "findings": len(findings), "allowlist": len(ALLOWLIST),
                          "new": [record(item) for item in new], "stale": [record(item) for item in stale],
                          "rules": dict(sorted(Counter(item.rule for item in findings).items()))}, ensure_ascii=False))
        return code
    for finding in new:
        print(f"NEW {finding.rule} {finding.path}:{finding.line} -> {finding.target}")
    for site in stale:
        print(f"STALE {site.rule} {site.path}:{site.evidence_line} -> {site.target} 请删除白名单项")
    counts = Counter(finding.rule for finding in findings)
    print(f"LAYER_GATE {'FAIL' if new or stale else 'PASS'} findings={len(findings)} "
          f"allowlist={len(ALLOWLIST)} new={len(new)} stale={len(stale)} rules={dict(sorted(counts.items()))}")
    return 1 if new or stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
