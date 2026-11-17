"""Original struct-based DAQmx fixtures, checked independently by npTDMS 1.10.0.
No upstream fixture/code is copied. Run after moon build --target js.
"""
from pathlib import Path
import io,json,struct,subprocess
import numpy as np
from nptdms import TdmsFile
ROOT=Path(__file__).resolve().parents[1]
PROGRAM=ROOT/'_build/js/debug/build/cmd/main/main.js'

def call(op,blob,**kw):
    p=subprocess.run(['node',str(PROGRAM),json.dumps(dict(protocol='moontdms/1',op=op,hex=blob.hex(),**kw))],capture_output=True,text=True,encoding='utf-8',timeout=30)
    if p.returncode:raise AssertionError(p.stdout+p.stderr)
    return json.loads(p.stdout)['result']

def reject(op,blob,**kw):
    p=subprocess.run(['node',str(PROGRAM),json.dumps(dict(protocol='moontdms/1',op=op,hex=blob.hex(),**kw))],capture_output=True,text=True,encoding='utf-8',timeout=30)
    assert p.returncode and 'error' in p.stdout,(p.stdout,p.stderr)

def text(s,e):
    b=s.encode();return struct.pack(e+'I',len(b))+b

def props(ps,e):
    out=struct.pack(e+'I',len(ps))
    for k,v in ps.items():
        out+=text(k,e)
        if isinstance(v,str):out+=struct.pack(e+'I',32)+text(v,e)
        elif isinstance(v,int):out+=struct.pack(e+'II',7,v)
        else:out+=struct.pack(e+'Id',10,v)
    return out

def segment(meta,raw,big=False,toc=142):
    e='>' if big else '<'
    return b'TDSm'+struct.pack('<I',toc+(64 if big else 0))+struct.pack(e+'IQQ',4713,len(meta)+len(raw),len(meta))+meta+raw

def fixture(channels,buffers,widths,count=4,big=False,digital=False):
    # Each scaler is (DAQmx type, buffer index, byte/bit offset, scale id).
    e='>' if big else '<';meta=struct.pack(e+'I',len(channels))
    for name,scalers,ps,*native in channels:
        marker=0x126a if digital else 0x1269
        meta+=text("/'acq'/'"+name+"'",e)+struct.pack(e+'IIIQI',marker,native[0] if native else 0xffffffff,1,count,len(scalers))
        for typ,buf,offset,idx in scalers:
            meta+=struct.pack(e+('IIIBI' if digital else 'IIIII'),typ,buf,offset,0,idx)
        meta+=struct.pack(e+'I',len(widths))+struct.pack(e+'I'*len(widths),*widths)+props(ps,e)
    return segment(meta,b''.join(buffers),big)

def linear(slope=0.25,intercept=1.5):
    return {'NI_Number_Of_Scales':2,'NI_Scale[1]_Scale_Type':'Linear','NI_Scale[1]_Linear_Input_Source':0,'NI_Scale[1]_Linear_Slope':slope,'NI_Scale[1]_Linear_Y_Intercept':intercept,'unit_string':'V','wf_increment':0.01,'wf_start_offset':0.5}

def ref(blob):return TdmsFile.read(io.BytesIO(blob))
def channels(td):return [c for g in td.groups() for c in g.channels()]
def validate(blob,physical=True):
    reference=ref(blob)
    moon=call('raw',blob)
    bypath={c['path']:c for c in moon['daqmx']}
    for c in channels(reference):
        expected=c.raw_scaler_data
        actual={s['id']:s['values'] for s in bypath[c.path]['scalers']}
        for sid,data in expected.items():
            assert actual[sid]==[str(int(v)) if np.issubdtype(data.dtype,np.integer) else float(v) for v in data],(c.path,sid,actual,data)
    if physical:
        normalized=call('physical',blob)
        objs={o['path']:o for o in normalized['objects']}
        for c in channels(reference):
            np.testing.assert_allclose(np.array(objs[c.path]['values'],dtype=float),c[:],rtol=1e-12,atol=1e-12)
        reread=ref(bytes.fromhex(normalized['hex']))
        for c in channels(reference):
            other=reread[c.group_name][c.name]
            np.testing.assert_allclose(other[:],c[:],rtol=1e-12,atol=1e-12)
            assert other.properties['NI_Scaling_Status']=='scaled'
    return reference

def crop(blob,big=False):
    source=ref(blob)
    paths=[c.path for c in channels(source)]
    out=bytes.fromhex(call('crop_raw',blob,paths=paths,start=1,end=3,big_endian=big)['hex'])
    after=ref(out)
    for c in channels(source):
        target=after[c.group_name][c.name]
        for idx,values in c.raw_scaler_data.items():
            np.testing.assert_array_equal(target.raw_scaler_data[idx],values[1:3])
        np.testing.assert_allclose(target[:],c[1:3],rtol=1e-12,atol=1e-12)
        for k,v in c.properties.items():
            if k=='wf_start_offset': assert target.properties[k]==v+c.properties['wf_increment']
            else:assert target.properties[k]==v
    validate(out)
    return out

def main():
    cases=0
    for big in [False,True]:
        e='>' if big else '<'
        blob=fixture([('voltage',[(3,0,0,0)],linear())],[struct.pack(e+'hhhh',-100,0,100,200)],[2],big=big)
        validate(blob);crop(blob,big);cases+=2
        # Two acquisition cards / two separately interleaved raw buffers.
        multi=fixture([('a',[(3,0,0,0)],linear()),('b',[(5,1,0,0)],linear(2.0,-3.0))],[struct.pack(e+'hhhh',1,2,3,4),struct.pack(e+'iiii',10,20,30,40)],[2,4],big=big)
        validate(multi);crop(multi,big);cases+=2
        # Multiple scalers feed a binary graph; Subtract follows NI/Excel right-left.
        for typ in ['Add','Subtract']:
            ps={'NI_Number_Of_Scales':3,'NI_Scale[2]_Scale_Type':typ,f'NI_Scale[2]_{typ}_Left_Operand_Input_Source':0,f'NI_Scale[2]_{typ}_Right_Operand_Input_Source':1}
            graph=fixture([('graph',[(3,0,0,0),(3,0,2,1)],ps)],[struct.pack(e+'hhhhhhhh',1,10,2,20,3,30,4,40)],[4],big=big)
            validate(graph);crop(graph,big);cases+=2
        # Digital bit 9 (second byte) shares a buffer with bit 0.
        digital=fixture([('line9',[(0,0,9,0)],{'NI_Number_Of_Scales':1}),('line0',[(0,0,0,0)],{'NI_Number_Of_Scales':1})],[bytes([1,2,0,0,0,2,1,0])],[2],big=big,digital=True)
        validate(digital);crop(digital,big);cases+=2
        # Exact 64-bit raw counts survive rewrite; physical linear output is float64.
        exact=fixture([('counter',[(6,0,0,0)],linear(1.0,0.0))],[struct.pack(e+'QQQQ',2**53+1,2**63+5,2**64-1,0)],[8],big=big)
        validate(exact);crop(exact,big);cases+=2
        # Polynomial, descending table, AdvancedAPI pass, chained polynomial.
        for typ in ['Polynomial','Table','AdvancedAPI']:
            ps={'NI_Number_Of_Scales':2,'NI_Scale[1]_Scale_Type':typ,f'NI_Scale[1]_{typ}_Input_Source':0}
            if typ=='Polynomial':ps.update({'NI_Scale[1]_Polynomial_Coefficients_Size':3,**{f'NI_Scale[1]_Polynomial_Coefficients[{i}]':v for i,v in enumerate([1.0,2.0,0.5])}})
            if typ=='Table':ps.update({'NI_Scale[1]_Table_Scaled_Values_Size':3,'NI_Scale[1]_Table_Pre_Scaled_Values_Size':3,**{f'NI_Scale[1]_Table_Scaled_Values[{i}]':v for i,v in enumerate([10.0,5.0,0.0])},**{f'NI_Scale[1]_Table_Pre_Scaled_Values[{i}]':v for i,v in enumerate([100.0,40.0,0.0])}})
            blob=fixture([('scaled',[(3,0,0,0)],ps)],[struct.pack(e+'hhhh',-1,0,5,12)],[2],big=big)
            validate(blob);crop(blob,big);cases+=2
        # Raw-only segment reuses DAQmx layout and appends samples.
        base=fixture([('v',[(3,0,0,0)],linear())],[struct.pack(e+'hhhh',1,2,3,4)],[2],big=big)
        repeated=base+segment(b'',struct.pack(e+'hhhh',5,6,7,8),big,toc=136)
        validate(repeated);crop(repeated,big);cases+=2
        # Fully repeated raw chunks within a segment.
        repeated=fixture([('v',[(3,0,0,0)],linear())],[struct.pack(e+'hhhhhhhh',1,2,3,4,5,6,7,8)],[2],big=big)
        validate(repeated);cases+=1
    # Typed DAQmx: raw sentinel denotes the ordinary typed stream.
    typed=fixture([('v',[(5,0,0,0)],{'NI_Number_Of_Scales':1,'NI_Scale[0]_Scale_Type':'Linear','NI_Scale[0]_Linear_Slope':2.0,'NI_Scale[0]_Linear_Y_Intercept':1.0},3)],[struct.pack('<iiii',1,2,3,4)],[4])
    normal=call('physical',typed)
    np.testing.assert_allclose([o['values'] for o in normal['objects'] if o['path']=="/'acq'/'v'"][0],ref(typed)['acq']['v'][:]);cases+=1

    # Every numeric DAQmx type code, with exact raw check and both endian outputs.
    for big in [False,True]:
        e='>' if big else '<'
        for typ,fmt,values in [(0,'B',[0,1,2,255]),(1,'b',[-128,-1,0,127]),(2,'H',[0,1,2,65535]),(3,'h',[-32768,-1,0,32767]),(4,'I',[0,1,2,2**32-1]),(5,'i',[-2**31,-1,0,2**31-1]),(6,'Q',[0,1,2,2**64-1]),(7,'q',[-2**63,-1,0,2**63-1]),(8,'f',[-2.5,0.0,1.25,100.0]),(9,'d',[-2.5,0.0,1.25,100.0])]:
            sample=fixture([('scalar',[(typ,0,0,0)],linear())],[struct.pack(e+fmt*4,*values)],[struct.calcsize(fmt)],big=big)
            validate(sample);crop(sample,big);cases+=2
    # Group and file scaling inheritance, then raw index reuse in a metadata-free segment.
    for path in ["/", "/'acq'"]:
        raw=struct.pack('<hhhh',-100,0,100,200)
        base=fixture([('voltage',[(3,0,0,0)],{})],[raw],[2])
        meta=struct.pack('<I',1)+text(path,'<')+struct.pack('<I',0xffffffff)+props(linear(),'<')
        inherited=segment(meta,b'',toc=6)+base
        validate(inherited);crop(inherited);cases+=2
    # No new metadata: prior scaler index is reused, all eight samples remain scaled.
    base=fixture([('voltage',[(3,0,0,0)],linear())],[struct.pack('<hhhh',1,2,3,4)],[2])
    appended=base+segment(b'',struct.pack('<hhhh',5,6,7,8),toc=136)
    validate(appended);cases+=1
    # Scaling cannot retroactively change samples from earlier segments.
    meta=struct.pack('<I',1)+text("/'acq'/'voltage'",'<')+struct.pack('<I',0xffffffff)+props({'NI_Scale[1]_Linear_Slope':2.0},'<')
    reject('raw',base+segment(meta,b'',toc=2));cases+=1
    # NI-documented alternate digital marker is read, canonical writer uses 1269.
    digital=fixture([('line',[(0,0,0,0)],{'NI_Number_Of_Scales':1})],[bytes([0,1,1,0])],[1],digital=True)
    alternate=digital.replace(struct.pack('<I',0x126a),struct.pack('<I',0x1369),1)
    assert call('raw',alternate)['daqmx'][0]['scalers'][0]['values']==['0','1','1','0'];cases+=1
    # An unknown scale remains exactly preserved by raw crop/write, even though
    # physical interpretation is explicitly unavailable.
    unknown=fixture([('v',[(3,0,0,0)],{'NI_Number_Of_Scales':2,'NI_Scale[1]_Scale_Type':'Thermocouple'})],[struct.pack('<hhhh',1,2,3,4)],[2])
    kept=bytes.fromhex(call('crop_raw',unknown,paths=["/'acq'/'v'"],start=1,end=3)['hex'])
    assert call('raw',kept)['daqmx'][0]['scalers'][0]['values']==['2','3'];reject('physical',kept);cases+=1
    # Unknown and malformed scale graphs fail explicitly, raw inspection remains available.
    for ps in [
        {'NI_Number_Of_Scales':2,'NI_Scale[1]_Scale_Type':'Thermocouple'},
        {'NI_Number_Of_Scales':2,'NI_Scale[1]_Scale_Type':'Linear','NI_Scale[1]_Linear_Input_Source':1,'NI_Scale[1]_Linear_Slope':1.0,'NI_Scale[1]_Linear_Y_Intercept':0.0},
        {'NI_Number_Of_Scales':2,'NI_Scale[1]_Scale_Type':'Linear','NI_Scale[1]_Linear_Input_Source':9,'NI_Scale[1]_Linear_Slope':1.0,'NI_Scale[1]_Linear_Y_Intercept':0.0},
    ]:
        blob=fixture([('bad',[(3,0,0,0)],ps)],[struct.pack('<hhhh',1,2,3,4)],[2]);call('raw',blob);reject('physical',blob);cases+=1
    for scalers,widths in [([(3,2,0,0)],[2]), ([(3,0,2,0)],[2]), ([(3,0,0,0),(3,0,0,0)],[2])]:
        blob=fixture([('bad',scalers,linear())],[b'\0'*8],widths);reject('raw',blob);cases+=1
    blob=fixture([('v',[(3,0,0,0)],linear())],[struct.pack('<hhhh',1,2,3,4)],[2])
    # Lead-in remains valid but trailing raw chunk is incomplete.
    short=bytearray(blob[:-1]);struct.pack_into('<Q',short,12,len(short)-28);reject('raw',bytes(short));cases+=1
    reject('crop_raw',blob,paths=["/'acq'/'v'"],start=2,end=8);cases+=1
    print(json.dumps({'daqmx_scenarios':cases,'reference':'npTDMS 1.10.0','result':'passed'}))
if __name__=='__main__':main()
