# -*- coding: utf-8 -*-
from pathlib import Path
import json,html
OUT=Path(__file__).parent;review=OUT/'review_floor5_v040'
views=[]
for p,label in [('F05A','잔류체 방'),('F05B','보스방')]:
    for degree in [70,90]:
        for side,title in [('Left','왼쪽'),('Right','오른쪽')]:views.append((p+'_HeadTurn'+str(degree)+'_'+side,f'{label} · {title} {degree}도'))
views += [('F05A_Overview','잔류체 방 전체'),('F05B_Overview','보스방 전체'),('F05A_iPad_MainCamera','잔류체 방 전투 시점'),('F05_iPad_MainCamera','보스방 전투 시점'),('CAM_F05_RewardSelection','빈 보상 받침대'),('CAM_F05_DescentDoor','하강 비석과 발판')]
header='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>5층 측면 배치 보강 · v040</title><style>body{margin:0 auto;padding:32px;max-width:1400px;background:#141619;color:#eee6d7;font:16px system-ui}p{line-height:1.7;color:#bdb4a7}h1{font-size:28px}a{color:#e0bb79}nav{display:flex;gap:20px;flex-wrap:wrap}figure{margin:36px 0}img{width:100%;border-radius:8px}figcaption{font-size:21px;margin:12px 0}.compare{display:grid;grid-template-columns:1fr 1fr;gap:14px}.compare img{width:100%}</style><h1>5층 · 좌우 기물 배치 보강</h1><p>잔류체 방과 보스방에 총 46개 기물을 추가했습니다. 원래 전투 카메라 위치에서 고개를 좌우 70도·90도로 돌린 모습입니다.<br>중앙 전투 공간과 빈 보상 받침대, 하강 구역은 확보했습니다. 두루마리 모델은 없는 상태입니다.</p><nav><a href="../DA_F05_TwoRooms_v040.blend">5층 Blender 파일</a><a href="../DA_F05_F06_F07_F08_F09_F10_Combined_v040_side_dressing.blend">5–10층 통합본</a><a href="../AUDIT_floor5_v040.json">검증 기록</a></nav>'''
body=''.join(f'<figure><figcaption>{html.escape(t)}</figcaption><a href="{n}.png"><img loading="lazy" src="{n}.png" alt="{html.escape(t)}"></a></figure>' for n,t in views)
(review/'index.html').write_text(header+body+'</html>',encoding='utf-8')
doc='''# 5층 측면 배치 보강 · v040

- 5층 잔류체 방과 보스방에 기존 GLB 기반 기물 46개를 추가.
- 잔류체 방: 기록 보관장·릴 서버·반향 재생기·가면 진열장·자료 상자를 연속 배치.
- 보스방: 가면 진열장·원본 검증 장치·기억 보관장·추출 장치를 높이가 다른 군집으로 배치.
- 기존 장식물을 일부 이동해 앞쪽 측면과 벽면 사이의 큰 빈 구간을 줄임.
- 90도 회전 시 방 밖이 드러나던 앞쪽 모서리에 벽·천장과 보관장을 이어 배치.
- 같은 메시와 재질을 공유하는 복사본으로 구성해 텍스처 중복 없이 보강.
- 두루마리 모델 없는 빈 보상 받침대, 장식용 문, 중앙 전투 공간, 하강 비석·발판 구성 유지.

## 산출물

- DA_F05_TwoRooms_v040.blend: 5층 두 장면.
- DA_F05_F06_F07_F08_F09_F10_Combined_v040_side_dressing.blend: 5–10층 통합본.
- review_floor5_v040/index.html: 검토 이미지 14장.
- AUDIT_floor5_v040.json: 공통 기물·텍스처·시야 검증.

## 확인

- 원래 전투 카메라와 동일한 눈 위치에서 좌우 70도·90도 렌더.
- 새 기물의 바운딩 박스가 기존 기물과 겹치거나 좌우 벽 밖으로 나가지 않음.
- 보상·하강 대상이 카메라 안에 들어오며, 검사한 시선에 장식 기물 가림 없음.
- 6–10층 기존 오브젝트 변환과 표시 상태 유지.
- 두루마리 모델 0개, 나중에 사용할 비표시 보상 위치 기준점 3개 유지.
- 기본 메시 삼각형: 잔류체 방 93,258개 / 보스방 140,858개. 베벨 등 렌더 시 추가분 제외.

## 재현

v039 통합본에서 dress_floor5_sides_v040.py와 close_floor5_side_corners_v040.py를 순서대로 한 번씩 실행한다. audit_floor5_v040.py로 검사하고 render_floor5_sides_v040.py 및 render_floor5_final_v040.py로 검토한다. save_floor5_v040.py로 새 버전 저장 후, 5층 전용 파일은 make_floor5_openable.py로 일반 Blender 시작 화면을 함께 저장한다.

Blender 배치 작업이며 앱 내보내기 및 게임 동작 연결은 포함하지 않는다.
'''
(OUT/'README_floor5_v040.md').write_text(doc,encoding='utf-8')
print('Packaged v040 review gallery')
