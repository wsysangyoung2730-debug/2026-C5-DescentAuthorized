"""Repair coherent limb/equipment skin regions without changing meshes or animation.

Run after author_natural_attacks.py. --actors may target an isolated audit copy.
Connected, welded surface components remain whole; no per-face splitting is used.
"""
from pathlib import Path
import argparse, hashlib, heapq, json
import numpy as np
from pxr import Usd, UsdGeom, UsdSkel, Vt

DEFAULT_ROOT = Path(__file__).resolve().parents[2] / 'DescentAuthorized/Resources/Reality/Actors'
parser = argparse.ArgumentParser()
parser.add_argument('--actors', type=Path, default=DEFAULT_ROOT)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()
BINDING_VERSION = '2026-09-30.1'

# (inner/full lateral boundary, lowest arm surface, shoulder cap, front limit).
# All coordinates are in the normalized, Z-up 3 m authoring space. The boundaries
# have continuous transitions; low claws and cuffs are never cut at z = 1.2 m.
REGIONS = {
 'RejectionExecutionResidual': (.48,.65,.75,2.53,.38),
 'OverloadResidual': (.40,.56,.57,2.48,.32),
 'BackflowBlockerResidual': (.55,.70,.15,2.42,.80),
 'QuarantineEnforcerResidual': (.25,.39,1.30,2.57,.22),
 'ExitReviewResidual': (.30,.46,.40,2.55,.22),
 'MemoryOmissionResidue': (.47,.75,.30,2.42,.80),
 'OriginalMemoryAdministrator': (.38,.57,1.34,2.30,.40),
 'RecordAdministrator': (.36,.55,1.04,2.28,.42),
 'ObservationAdministrator': (.34,.53,.77,2.17,.10),
 'ObservationResidue': (.32,.55,.31,2.12,.30),
 'CoordinateResidue': (.30,.47,1.60,2.43,.23),
 'CoordinateAdministrator': (.32,.49,1.14,2.40,.23),
 'CausalityResidue': (.31,.52,1.30,2.50,.25),
 'CausalityAdministrator': (.30,.48,1.65,2.59,.23),
 'ResponsibilityAuditAdministrator': (.31,.49,1.19,2.65,.20),
 'SignatureMimicResidual': (.28,.45,1.70,2.58,.16),
 'ConsentCustodianResidual': (.28,.45,1.35,2.56,.16),
 'VoluntaryQuarantineAdministrator': (.27,.44,1.34,2.56,.20),
 'SealMaintenanceAdministrator': (.32,.50,1.19,2.59,.22),
 'IdentityComparisonResidual': (.27,.43,1.39,2.54,.16),
 'FinalAuthorizationAdministrator': (.27,.44,1.30,2.26,-.16),
}
RIGID_ARMS = {
 'RejectionExecutionResidual','OverloadResidual','BackflowBlockerResidual',
 'QuarantineEnforcerResidual','ExitReviewResidual','MemoryOmissionResidue',
 'OriginalMemoryAdministrator','RecordAdministrator','ObservationAdministrator',
 'ObservationResidue',
}
STAFFS = {
 'CoordinateAdministrator': (-.73,-.04,.22),
 'ResponsibilityAuditAdministrator': (-.70,-.22,.21),
 'SealMaintenanceAdministrator': (-.72,-.22,.21),
 'FinalAuthorizationAdministrator': (.61,-1.10,.23),
}
BOOKS = {'SignatureMimicResidual','ConsentCustodianResidual','IdentityComparisonResidual','CausalityAdministrator'}

def smooth(v):
    t=np.clip(v,0,1)
    return t*t*(3-2*t)

def weld_components(points, counts, indices):
    unique,first,inverse=np.unique(np.round(points,5),axis=0,return_index=True,return_inverse=True)
    parents=np.arange(len(first));sizes=np.ones(len(first),dtype=int)
    def find(v):
        while parents[v]!=v:
            parents[v]=parents[parents[v]];v=parents[v]
        return v
    off=0
    for count in counts:
        face=inverse[indices[off:off+count]];off+=count
        for v in face[1:]:
            a=find(face[0]);b=find(v)
            if a==b:continue
            if sizes[a]<sizes[b]:a,b=b,a
            parents[b]=a;sizes[a]+=sizes[b]
    labels=np.array([find(v) for v in range(len(first))])
    return first,inverse,labels

def surface_distances(points, edges, seeds):
    """Shortest paths stay on the mesh instead of jumping from cuff to apron."""
    adjacency=[[] for _ in points]
    for a,b in edges:
        length=float(np.linalg.norm(points[a]-points[b]))
        adjacency[a].append((b,length));adjacency[b].append((a,length))
    distance=np.full(len(points),np.inf)
    queue=[(0.,int(i)) for i in np.flatnonzero(seeds)]
    for _,i in queue:distance[i]=0
    heapq.heapify(queue)
    while queue:
        cost,i=heapq.heappop(queue)
        if cost!=distance[i]:continue
        for j,length in adjacency[i]:
            candidate=cost+length
            if candidate<distance[j]:
                distance[j]=candidate;heapq.heappush(queue,(candidate,j))
    return distance

def joint_index(joints, *names):
    for wanted in names:
        for index,joint in enumerate(joints):
            leaf=str(joint).split('/')[-1].replace(':','_')
            if leaf==wanted:return index
    return None

def preserved_content_digest(stage):
    """Hash every authored attribute except the two edited skin primvars.

    Array elements are hashed individually, avoiding truncated array formatting.
    This covers meshes, UVs, normals, joints, bind poses and every animation sample.
    """
    digest=hashlib.sha256()
    excluded={'primvars:skel:jointIndices','primvars:skel:jointWeights',
              'primvars:skel:jointIndices:indices','primvars:skel:jointWeights:indices'}
    for prim in stage.Traverse():
        for attr in sorted(prim.GetAttributes(),key=lambda item:item.GetName()):
            if attr.GetName() in excluded:continue
            digest.update(str(attr.GetPath()).encode())
            for time in [None]+attr.GetTimeSamples():
                value=attr.Get() if time is None else attr.Get(time)
                digest.update(str(time).encode())
                if type(value).__module__=='pxr.Vt':
                    for item in value:digest.update(repr(item).encode())
                else:digest.update(repr(value).encode())
    return digest.hexdigest()

reports=[]
for folder in sorted(args.actors.iterdir()):
    path=folder/'articulated.usdc'
    if not path.exists() or folder.name not in REGIONS:continue
    stage=Usd.Stage.Open(str(path))
    if stage.GetRootLayer().customLayerData.get('naturalAttackBindingVersion')==BINDING_VERSION:
        reports.append({'actor':folder.name,'alreadyRepaired':True});continue
    preserved_before=preserved_content_digest(stage)
    skeleton=next(UsdSkel.Skeleton(p) for p in stage.Traverse() if p.IsA(UsdSkel.Skeleton))
    joints=list(skeleton.GetJointsAttr().Get());joint_count=len(joints)
    bind_matrices=np.array(skeleton.GetBindTransformsAttr().Get());positions=bind_matrices[:,3,:3]
    root=joint_index(joints,'root','mixamorig_Hips');chest=joint_index(joints,'chest','spine','mixamorig_Spine2');head=joint_index(joints,'head','mixamorig_Head')
    arms={side:[joint_index(joints,part+'_'+side,'mixamorig_'+('Left' if side=='L' else 'Right')+mix) for part,mix in [('upper_arm','Arm'),('forearm','ForeArm'),('hand','Hand')]] for side in ['L','R']}
    for side in arms:
        if arms[side][0] is None:arms[side]=[joint_index(joints,'arm_'+side)]*3
    arm_desc={side:[i for i,j in enumerate(joints) if j==joints[chain[0]] or str(j).startswith(str(joints[chain[0]])+'/')] for side,chain in arms.items()}
    meshes=[]
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):continue
        mesh=UsdGeom.Mesh(prim);binding=UsdSkel.BindingAPI(prim);idvar=binding.GetJointIndicesPrimvar();weightvar=binding.GetJointWeightsPrimvar()
        if not idvar or not weightvar:continue
        points=np.array(mesh.GetPointsAttr().Get(),dtype=float);counts=np.array(mesh.GetFaceVertexCountsAttr().Get(),int);indices=np.array(mesh.GetFaceVertexIndicesAttr().Get(),int)
        old_ids=np.array(idvar.ComputeFlattened(),int).reshape(len(points),-1);old_w=np.array(weightvar.ComputeFlattened(),float).reshape(old_ids.shape)
        assert old_ids.min()>=0 and old_ids.max()<joint_count, (folder.name,'invalid input joint')
        dense=np.zeros((len(points),joint_count));np.add.at(dense,(np.arange(len(points))[:,None],old_ids),old_w)
        dense/=np.maximum(dense.sum(1,keepdims=True),1e-12)
        first,inverse,components=weld_components(points,counts,indices);p=points[first];n=len(first)
        welded=np.zeros((n,joint_count));np.add.at(welded,inverse,dense);welded/=np.bincount(inverse)[:,None]
        before=welded.copy();x,y,z=p.T;inner,outer,low,top,front=REGIONS[folder.name]
        all_arm=sorted(set(arm_desc['L']+arm_desc['R']))
        body=before.copy();body[:,all_arm]=0
        missing=body.sum(1)<1e-8
        body[missing,chest]=1
        body/=np.maximum(body.sum(1,keepdims=True),1e-12)
        # Stable central lower body. Retain cloth/leg weighting rather than allowing
        # distant hand bones to pull the skirt, pedestal or feet upward.
        masks={};new=body.copy()
        for side,sign in [('L',1),('R',-1)]:
            lateral=smooth((sign*x-inner)/(outer-inner))
            if folder.name=='MemoryOmissionResidue':
                lateral=np.maximum(lateral,smooth((sign*x-.32)/.20)*smooth((-y-.43)/.25))
            mask=lateral*smooth((z-low)/.22)*(1-smooth((z-top)/.22))*(1-smooth((y-front)/.25))
            if folder.name=='ObservationAdministrator' and side=='R':
                cannon=smooth((-x-.43)/.15)*smooth((-y-.34)/.16)*smooth((z-.50)/.12)*(1-smooth((z-1.90)/.18))
                mask=np.maximum(mask,cannon)
            # The apron behind the hook and the rear claw drape are body surfaces.
            # Their front-facing weapons remain separate, coherent components.
            if folder.name=='BackflowBlockerResidual':
                mask*=1-smooth((y-.25)/.20)*smooth((z-1.60)/.25)
                mask*=1-smooth((y+.08)/.16)*(1-smooth((z-1.48)/.25))*(1-smooth((np.abs(x)-.64)/.12))
            if folder.name=='MemoryOmissionResidue':
                mask*=1-smooth((y+.02)/.20)*(1-smooth((z-1.35)/.25))*(1-smooth((np.abs(x)-.76)/.18))
            if folder.name=='RejectionExecutionResidual':
                mask*=1-smooth((y+.18)/.22)*(1-smooth((z-1.36)/.25))*(1-smooth((np.abs(x)-.65)/.15))
            if folder.name=='OverloadResidual':
                mask*=1-smooth((y+.22)/.20)*(1-smooth((z-1.38)/.25))*(1-smooth((np.abs(x)-.58)/.15))
            if folder.name=='RecordAdministrator':
                mask*=1-smooth((y-.55)/.30)
            masks[side]=mask
            chain=list(dict.fromkeys(arms[side]));influence=np.zeros_like(body)
            if folder.name in RIGID_ARMS:
                influence[:,chain[0]]=1
            else:
                # Smooth nearest-joint allocation within an already isolated arm.
                # This removes the old z=1.2 domain cliff without crossing the torso.
                d=np.linalg.norm(p[:,None,:]-positions[chain][None,:,:],axis=2)
                local=1/np.maximum(d,.07)**4;local/=local.sum(1,keepdims=True)
                for j,index in enumerate(chain):influence[:,index]=local[:,j]
            new=new*(1-mask[:,None])+influence*mask[:,None]
        if folder.name=='BackflowBlockerResidual':
            # The hook, cuff and apron touch in projected space but connect through
            # different surface paths. A spatial box cannot separate this fused mesh.
            offset=np.r_[0,np.cumsum(counts)]
            edges=[]
            for f in range(len(counts)):
                face=inverse[indices[offset[f]:offset[f+1]]]
                edges.extend(zip(face,np.roll(face,-1)))
            edges=np.unique(np.sort(np.array(edges),axis=1),axis=0)
            stable=(np.abs(x)<.36)|(z<.35)|((y>.40)&(z>1.65)&(np.abs(x)<.55))|(z>2.62)
            body_distance=surface_distances(p,edges,stable)
            for side,sign in [('L',1),('R',-1)]:
                seeds=(sign*x>.80)&(z>.40)&(z<2.12)&(y<.25)
                arm_distance=surface_distances(p,edges,seeds)
                valid=np.isfinite(body_distance)&np.isfinite(arm_distance)
                blend=np.zeros(n)
                blend[valid]=smooth((body_distance[valid]-arm_distance[valid]+.06)/.26)
                # Apply only to the mixed main component; isolated weapon pieces
                # receive their explicit coherent assignment below.
                for label in np.unique(components):
                    vv=np.flatnonzero(components==label)
                    if len(vv)<4000:continue
                    take=vv[sign*x[vv]>0]
                    new[take]=body[take]*(1-blend[take,None])
                    new[take,arms[side][0]]+=blend[take]
        rigid_components=0;staff_components=0;book_components=0
        for label in np.unique(components):
            vv=np.flatnonzero(components==label);q=p[vv];lo=q.min(0);hi=q.max(0);center=q.mean(0);extent=hi-lo
            if folder.name=='QuarantineEnforcerResidual' and hi[1]<.02 and lo[2]>.85 and hi[2]<1.95 and (hi[0]<-.36 or lo[0]>.36):
                side='R' if center[0]<0 else 'L'
                new[vv]=0;new[vv,arms[side][0]]=1;rigid_components+=1;continue
            if folder.name=='CoordinateResidue' and hi[1]<.12 and lo[2]>.80 and hi[2]<1.72 and (hi[0]<-.60 or lo[0]>.60):
                side='R' if center[0]<0 else 'L'
                new[vv]=0;new[vv,arms[side][0]]=1;rigid_components+=1;continue
            if folder.name=='CoordinateAdministrator' and lo[1]>.08 and lo[2]>1.20:
                new[vv]=0;new[vv,chest]=1;rigid_components+=1;continue
            if folder.name=='FinalAuthorizationAdministrator' and (lo[1]>-.20 or (len(vv)>700 and hi[2]<2.25 and lo[2]<.25)):
                new[vv]=body[vv];continue
            if folder.name=='BackflowBlockerResidual' and hi[0]<-.54 and lo[2]>.40 and hi[2]<2.55 and hi[1]<.35:
                new[vv]=0;new[vv,arms['R'][0]]=1;rigid_components+=1;continue
            if folder.name=='BackflowBlockerResidual' and lo[0]<-.60 and hi[0]<-.30 and lo[2]>.90 and hi[2]<1.36:
                new[vv]=body[vv];continue
            if folder.name=='QuarantineEnforcerResidual' and (abs(center[0])<.375 or hi[2]<1.40 or (lo[1]>.20 and extent[2]>.65)):
                new[vv]=body[vv];continue
            if folder.name=='ExitReviewResidual' and lo[2]<.70 and hi[2]<2.05 and extent[2]>1.15 and extent[1]>.25:
                new[vv]=body[vv];continue
            if folder.name=='CausalityResidue' and hi[2]<1.70 and hi[0]<-.25:
                new[vv]=body[vv];continue
            if folder.name=='ObservationAdministrator' and lo[2]<.20 and hi[2]>2.2 and hi[0]>.55 and lo[0]>-.70 and hi[1]<.45:
                new[vv]=body[vv];continue
            if folder.name=='ObservationResidue' and lo[0]<-.55 and hi[0]>.55 and hi[2]>2.7:
                new[vv]=0;new[vv,chest]=1;rigid_components+=1;continue
            # Full lower-leg/robe components cannot follow an arm merely because
            # their outer knee or hem enters a shoulder-side spatial region.
            if folder.name not in {'ObservationResidue','RecordAdministrator'} and lo[2]<.30 and hi[2]<2.05:
                new[vv]=body[vv];continue
            if folder.name=='OverloadResidual' and len(vv)>2000:
                grounded=vv[z[vv]<.85];new[grounded]=body[grounded]
            if folder.name=='CausalityResidue' and hi[0]<-.07 and lo[0]>-.60 and lo[2]>1.35 and hi[2]>2.50:
                new[vv]=0;new[vv,chest]=1;rigid_components+=1;continue
            # Long isolated arms, shields and claw strands are connected objects.
            # Keep their full extent, including tips below the generic body band.
            if folder.name in {'CoordinateResidue','ObservationResidue','ExitReviewResidual','QuarantineEnforcerResidual'}:
                for side,sign in [('L',1),('R',-1)]:
                    edge=float(np.min(sign*q[:,0]));allowed_low=0 if folder.name=='ObservationResidue' else .30
                    if edge>(.27 if folder.name=='ObservationResidue' else .33) and lo[2]>=allowed_low-.001 and hi[2]>1.3 and len(vv)<2000:
                        new[vv]=0;new[vv,arms[side][0]]=1;rigid_components+=1;break
                else:side=None
                if side is not None:continue
            # Pin coherent staff parts including their head ornament. The old height
            # threshold bisected long poles and made their tips follow the head.
            staff=STAFFS.get(folder.name)
            if staff:
                sx,sy,radius=staff
                radial=np.linalg.norm(q[:,:2]-np.array([sx,sy]),axis=1)
                if np.mean(radial<radius)>.55 and extent[0]<.72 and extent[1]<.75 and len(vv)<2000:
                    new[vv]=0;new[vv,root]=1;staff_components+=1;continue
            # Whole book/case panels stay with their original rigid equipment bone.
            book=joint_index(joints,'equipment_book')
            if book is not None and folder.name in BOOKS and len(vv)<2200 and extent[2]<1.35:
                if before[vv,book].mean()>.12:
                    new[vv]=0;new[vv,book]=1;book_components+=1;continue
            # Separate solid back pieces/crowns are single surfaces, not cloth.
            back=joint_index(joints,'equipment_back')
            if back is not None and len(vv)<1600 and lo[2]>1.30 and extent[2]<1.7 and before[vv,back].mean()>.18:
                new[vv]=0;new[vv,back]=1;rigid_components+=1;continue
            if len(vv)>2200 or extent[2]>1.65 or lo[2]<.30:continue
            for side,sign in [('L',1),('R',-1)]:
                side_min=float(np.min(sign*q[:,0]));side_center=sign*center[0]
                coherence=float(np.mean(masks[side][vv]>.40))
                arm_vote=float(before[vv][:,arm_desc[side]].sum(1).mean())
                if side_min<inner*.48 or center[2]<low+.03 or center[2]>top+.10:continue
                if coherence>.55 or (arm_vote>.35 and side_center>inner and center[1]<front+.15):
                    bone=arms[side][0] if folder.name in RIGID_ARMS else arms[side][int(np.argmin(np.linalg.norm(positions[arms[side]]-center,axis=1)))]
                    new[vv]=0;new[vv,bone]=1;rigid_components+=1;break
        # Legacy blade/shield parts reach below the body's ankle rule. Their full
        # connected component, including low tips, follows the owning shoulder.
        if folder.name=='RecordAdministrator':
            for label in np.unique(components):
                vv=np.flatnonzero(components==label);q=p[vv];lo=q.min(0);hi=q.max(0)
                side='R' if hi[0]<-.40 and lo[1]<-.20 else ('L' if lo[0]>.40 and hi[2]>1.5 else None)
                if side:
                    new[vv]=0;new[vv,arms[side][0]]=1;rigid_components+=1
        if folder.name=='RejectionExecutionResidual':
            # The fused apron is part of the body, while stamp and shield are
            # separate components. Restrict its shoulder blend above the belt.
            for label in np.unique(components):
                vv=np.flatnonzero(components==label)
                if len(vv)<4000:continue
                blend=smooth((z[vv]-1.55)/.30)
                new[vv]=new[vv]*blend[:,None]+body[vv]*(1-blend[:,None])
        if folder.name=='ObservationAdministrator':
            # The central low robe was accidentally caught by the abs(x) equipment
            # mask. No cannon surface lies below this band in the rest model.
            locked=z<.60;new[locked]=body[locked]
        # Identical rest-position vertices must share precisely the same weights.
        # Preserve continuous vertices; never split faces to fake rigid equipment.
        new/=np.maximum(new.sum(1,keepdims=True),1e-12)
        largest=np.argsort(new,axis=1)[:,-4:][:,::-1];values=np.take_along_axis(new,largest,axis=1);values/=np.maximum(values.sum(1,keepdims=True),1e-12)
        repaired_ids=largest[inverse];repaired_weights=values[inverse]
        assert np.isfinite(repaired_weights).all() and np.min(repaired_weights)>=0
        assert np.max(np.abs(repaired_weights.sum(1)-1))<1e-6
        assert repaired_ids.max()<joint_count and repaired_ids.min()>=0
        ids=binding.CreateJointIndicesPrimvar(False,4);weights=binding.CreateJointWeightsPrimvar(False,4)
        for pv,data in [(ids,Vt.IntArray(repaired_ids.reshape(-1).tolist())),(weights,Vt.FloatArray(repaired_weights.reshape(-1).tolist()))]:
            pv.Set(data);pv.SetElementSize(4);pv.SetInterpolation('vertex');pv.BlockIndices()
        delta=np.abs(new-before).sum(1)
        meshes.append({'mesh':str(prim.GetPath()),'vertices':len(points),'weldedVertices':n,'connectedComponents':len(np.unique(components)),'rigidComponents':rigid_components,'staffComponents':staff_components,'bookComponents':book_components,'changedWeldedVertices':int(np.count_nonzero(delta>1e-4))})
    preserved_after=preserved_content_digest(stage)
    assert preserved_before==preserved_after, (folder.name,'non-binding content changed')
    metadata=dict(stage.GetRootLayer().customLayerData)
    metadata['naturalAttackBindingVersion']=BINDING_VERSION
    stage.GetRootLayer().customLayerData=metadata
    stage.GetRootLayer().Save()
    reports.append({'actor':folder.name,'bindingVersion':BINDING_VERSION,
                    'preservedContentSHA256':preserved_after,'meshes':meshes})
    print(folder.name,meshes,flush=True)
args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
