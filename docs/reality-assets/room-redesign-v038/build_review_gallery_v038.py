# -*- coding: utf-8 -*-
from pathlib import Path
import html
out=Path(__file__).parent/'review_v038'
groups=[('6층 돔과 전투 시야',['F06B_DomeReview','F08_iPad_MainCamera','F06_iPad_MainCamera']),('6·7층 전체 공간',[p+'_RedesignOverview' for p in ['F06A','F06B','F07A','F07B']]),('보상과 하강 시점',['CAM_'+p+'_'+k for p in ['F06','F07','F08','F09','F10'] for k in ['RewardSelection','DescentDoor']]),('좌우 회전 시야',[p+'_SideCheck_'+side for p in ['F06A','F06B','F07A','F07B','F08A','F08B','F09','F10'] for side in ['Left','Right']])]
labels={'F06B_DomeReview':'6층 보스 천장 돔','F08_iPad_MainCamera':'8층 메인 전투 시점','F06_iPad_MainCamera':'6층 메인 전투 시점'}
for p in ['F06','F07','F08','F09','F10']:
 labels['CAM_'+p+'_RewardSelection']=str(int(p[1:]))+'층 '+('기존 책상 상호작용' if p=='F10' else '두루마리 선택')
 labels['CAM_'+p+'_DescentDoor']=str(int(p[1:]))+'층 하강문·비석·발판'
for p in ['F06A','F06B','F07A','F07B','F08A','F08B','F09','F10']:
 room=str(int(p[1:3]))+'층 '+('잔재방' if p.endswith('A') else '보스방' if p.endswith('B') else '')
 labels[p+'_RedesignOverview']=room+' 전체'
 for side,ko in [('Left','왼쪽'),('Right','오른쪽')]:labels[p+'_SideCheck_'+side]=room+' '+ko
body=[]
for title,names in groups:
 body.append('<section><h2>'+title+'</h2><div class="grid">')
 for n in names:body.append(f'<figure><a href="{n}.png"><img loading="lazy" src="{n}.png" alt="{html.escape(labels.get(n,n))}"></a><figcaption>{html.escape(labels.get(n,n))}</figcaption></figure>')
 body.append('</div></section>')
(out/'index.html').write_text('''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>C5 공간 배치 · v038</title><style>body{margin:0;background:#101419;color:#e1e8ee;font:16px system-ui;line-height:1.6}header,main{max-width:1500px;margin:auto;padding:24px}h1{font-size:30px;margin:0}h2{margin-top:35px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:18px}figure{margin:0;background:#1c242d;border-radius:10px;overflow:hidden}img{width:100%;display:block}figcaption{padding:12px}p{color:#aebecb}a{color:#8dd4ee}@media(max-width:500px){.grid{grid-template-columns:1fr}}</style><header><h1>C5 · 6–10층 공간 배치</h1><p>v038 · 기존 기물 104종 활용 · 측면 밀도 보강 · 보상/하강 시야 점검 · 6층 보스 천장 돔</p><p>Blender 카메라 검토 이미지입니다. 실제 앱에 반영하기 위한 내보내기와 기기 검증은 별도입니다. 10층은 기존 책상 상호작용을 유지합니다.</p></header><main>'''+''.join(body)+'</main></html>')
print(out/'index.html')
