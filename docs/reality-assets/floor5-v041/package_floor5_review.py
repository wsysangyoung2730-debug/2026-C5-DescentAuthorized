# -*- coding: utf-8 -*-
from pathlib import Path
import json,html
root=Path(__file__).parent;out=root/'review_floor5_v039'
views=[('F05A_Overview','5층 · 기억 누락 잔류체 방'),('F05B_Overview','5층 · 기억 원본 관리자 방'),('CAM_F05_RewardSelection','보상 받침대 · 두루마리 없음'),('CAM_F05_DescentDoor','하강 · 비석과 두 발판'),('F05A_iPad_MainCamera','잔류체 방 · 전투 시점'),('F05_iPad_MainCamera','보스방 · 전투 시점'),('F05A_SideCheck_Left','잔류체 방 · 왼쪽'),('F05A_SideCheck_Right','잔류체 방 · 오른쪽'),('F05B_SideCheck_Left','보스방 · 왼쪽'),('F05B_SideCheck_Right','보스방 · 오른쪽')]
head='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>5층 두 공간 · Blender v039</title><style>body{background:#151719;color:#eae6dc;font:16px system-ui;margin:0 auto;max-width:1440px;padding:36px}h1{font-size:28px}p{color:#bcb6a9;line-height:1.7}figure{margin:30px 0 48px}img{width:100%;border-radius:10px;display:block}figcaption{margin:12px 0;font-size:20px}a{color:#d8b878}.facts{border-left:3px solid #ad8446;padding:4px 18px}nav{display:flex;gap:16px;flex-wrap:wrap}footer{padding:32px 0;color:#aaa}</style><h1>5층 · 기억 원본 보관 구역</h1><p>Blender 배치 결과 · v039</p><div class="facts"><p>잔류체 방: 낮은 아치형 천장, 기록·반향·기억 누락 기물.<br>보스방: 격자형 천장, 가면 진열·원본 신원 대조·기억 추출 기물.<br>제공 기물 20종 사용. 문은 봉인된 벽면 장식. 실제 이동은 별도 개방 통로.<br>보상 받침대는 빈 상태이며, 두루마리 3개 모델과 등장 애니메이션을 제거했습니다.</p></div><nav><a href="../DA_F05_TwoRooms_v039.blend">5층 전용 Blender</a><a href="../DA_F05_F06_F07_F08_F09_F10_Combined_v039_floor5.blend">5–10층 통합 Blender</a><a href="../AUDIT_floor5_v039.json">검증 기록</a></nav>'''
body=''.join(f'<figure id="{n}"><figcaption>{html.escape(t)}</figcaption><a href="{n}.png"><img src="{n}.png" alt="{html.escape(t)}" loading="lazy"></a></figure>' for n,t in views)
(out/'index.html').write_text(head+body+'<footer>공간 모델링·배치 결과입니다. 앱 연결과 보상·이동 동작은 아직 구현하지 않았습니다.</footer></html>',encoding='utf-8')
a=json.loads((root/'AUDIT_floor5_v039.json').read_text())
text='''# 5층 두 장면 · Blender v039

## 결과

- DA_F05_TwoRooms_v039.blend: 5층 전용 두 장면, 텍스처 포함.
- DA_F05_F06_F07_F08_F09_F10_Combined_v039_floor5.blend: 기존 6–10층을 보존한 통합본.
- review_floor5_v039/index.html: 전체·전투·좌우·보상·하강 카메라 갤러리.

## 장면

- DA_F05A_MemoryOmissionResidue: 기록 누락·반향 재생 보관실, 아치형 천장.
- DA_F05B_OriginalMemoryAdministrator: 원본 신원 대조·기억 추출실, 격자형 천장.

## 공통 배치

마법 입력판, 전투 발판, 스폰 및 이동 기준점, 보스방 보상 받침대, 하강 비석·입력 발판·하강 발판을 배치했다. 장식 문에는 봉인 줄을 배치하고 실제 이동 통로와 분리했다. 하강문 형태의 5층 기물도 장식용이다.

사용자 추가 요청에 따라 5층 보스방의 보상 두루마리 3개와 등장 애니메이션은 제거했다. ANCHOR_F05_RewardSlot_Left/Center/Right는 보상 받침대에 종속된 비표시 기준점이다. 이후 동작 연결 시 위치를 확인한다. 다른 층의 두루마리는 변경하지 않았다.

## 검증

- 원본 13개 장면의 오브젝트 변환 및 표시 상태 비교 통과.
- 5층 기물 20종 모두 렌더 가능한 장면에 배치.
- 보상·하강 카메라에 대상 전체 포함 및 기물 가림 표본 검사 통과.
- 참조 텍스처 누락 없음. 저장한 5층 전용 파일을 다시 열어 검증.
- 장식 닫힌 문의 복사본만 약 186만 → 3.5만 삼각형으로 경량화. 원본 GLB 보존.
'''
for p,r in a['rooms'].items():text+=f"- {p}: 기본 메시 삼각형 {r['triangles']:,}개 (렌더 시 베벨 등 추가분 제외).\n"
text+='''
## 재현 순서

기존 v038 통합 파일에서 실행한다. 각 추가 단계는 한 번만 실행하며, 새 장면이 이미 존재하면 setup을 다시 실행하지 않는다.

1. build_floor5_v039.py: setup() → 각 architecture(p) → props(p) → finish(p).
2. refine_floor5_v039.py.
3. finalize_floor5_v039.py: 최종 방향·장식 문 경량화·보상 두루마리 제거.
4. audit_floor5_v039.py → build_floor5_v039.py의 save().
5. render_floor5_v039.py: 10개 카메라 검토 렌더.

## 범위

Blender 모델링·배치·검토까지 수행했다. 게임 코드 변경, 앱용 내보내기, 실제 전투·보상·하강 동작 연결은 이번 작업에 포함하지 않는다.
'''
(root/'README_floor5_v039.md').write_text(text,encoding='utf-8')
print('Saved gallery and notes')
