"""Independent TDMS compatibility checks; numpy/npTDMS are dev-only."""
from pathlib import Path
import io,json,math,os,struct,subprocess,sys
import numpy as np
from nptdms import TdmsFile,TdmsWriter,RootObject,GroupObject,ChannelObject
ROOT=Path(__file__).resolve().parents[1]
PROGRAM=ROOT/'_build/js/debug/build/cmd/main/main.js'

def call(op,**fields):
    request={'protocol':'moontdms/1','op':op,**fields}
    result=subprocess.run(['node',str(PROGRAM),json.dumps(request,ensure_ascii=True)],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=30)
    if result.returncode: raise AssertionError(result.stdout+'\n'+result.stderr)
    return json.loads(result.stdout)['result']

def scalar(v):
    if isinstance(v,(bool,np.bool_)):return bool(v)
    if isinstance(v,(int,np.integer)):return str(int(v))
    if isinstance(v,(float,np.floating)):
        v=float(v)
        if math.isnan(v):return 'NaN'
        if math.isinf(v):return 'Infinity' if v>0 else '-Infinity'
        return v
    return str(v)

def compare(blob):
    moon=call('decode',hex=blob.hex())['objects']
    reference=TdmsFile.read(io.BytesIO(blob),raw_timestamps=True)
    for obj in moon:
        if len(obj['path'].split("/'"))!=3:continue
        # Test names here do not contain quoted slashes; the separate path tests do.
        path=obj['path'];g,c=[part.rstrip("'") for part in path.split("/'")[1:]]
        channel=reference[g][c]
        expected=channel[:]
        for prop in obj['properties']:
            value=channel.properties[prop['name']]
            if prop['type']==68:value={'seconds':str(int(value.seconds)),'fractions':str(int(value.second_fractions))}
            else:value=scalar(value)
            assert prop['value']==value,(path,prop,value)
        if obj['type']==68:
            expected=[{'seconds':str(int(s)),'fractions':str(int(f))} for s,f in zip(expected.seconds,expected.second_fractions)]
        else:expected=[scalar(v) for v in expected]
        assert obj['values']==expected,(path,obj['values'],expected)
    return len(moon)

def segment(meta,raw,toc=14,big=False):
    endian='>' if big else '<'
    return b'TDSm'+struct.pack('<I',toc)+struct.pack(endian+'IQQ',4713,len(meta)+len(raw),len(meta))+meta+raw

def text(s,endian='<'):
    b=s.encode('utf-8');return struct.pack(endian+'I',len(b))+b

def standard(kind,values,fmt,big=False,interleaved=False):
    e='>' if big else '<'
    records=[]
    for name in ['a','b']:
        records.append(text("/'g'/'"+name+"'",e)+struct.pack(e+'IIIQI',20,kind,1,len(values),0))
    meta=struct.pack(e+'I',2)+b''.join(records)
    seq=[v for pair in zip(values,values) for v in pair] if interleaved else list(values)*2
    raw=struct.pack(e+fmt*len(seq),*seq)
    return segment(meta,raw,14+(64 if big else 0)+(32 if interleaved else 0),big)

def main():
    if '--no-build' not in sys.argv:
        subprocess.run(['moon','build','--target','js','--deny-warn'],cwd=ROOT,check=True)
    count=0
    for kind,fmt,values in [(1,'b',[-128,0,127]),(2,'h',[-32768,1,32767]),(3,'i',[-2147483648,0,2147483647]),(4,'q',[-9223372036854775808,3,9223372036854775807]),(5,'B',[0,3,255]),(6,'H',[0,2,65535]),(7,'I',[0,1,4294967295]),(8,'Q',[0,1,18446744073709551615]),(9,'f',[-1.5,0,3.25]),(10,'d',[-1e100,0,1e100]),(33,'B',[0,1,1])]:
        for big in [False,True]:
            for interleaved in [False,True]:
                blob=standard(kind,values,fmt,big,interleaved)
                compare(blob);count+=1
    for dtype in [np.int16,np.uint64,np.float32,np.float64,np.bool_]:
        stream=io.BytesIO()
        with TdmsWriter(stream, version=4713) as writer:
            for i in range(3):
                data=np.array([i,i+1,i+2],dtype=dtype)
                writer.write_segment([RootObject(properties={'title':'measurement'}),GroupObject('g'),ChannelObject('g','a',data,properties={'unit_string':'V','wf_increment':0.25})])
        compare(stream.getvalue());count+=1
    stream=io.BytesIO()
    with TdmsWriter(stream, version=4713) as writer:
        writer.write_segment([ChannelObject('g','a',np.array(['a','娴嬮噺','',"a'b"]))])
        writer.write_segment([ChannelObject('g','a',np.array(['尾']))])
    compare(stream.getvalue());count+=1
    # Timestamp endianness is independently packed, including maximum fractions.
    for big in [False,True]:
        e='>' if big else '<'
        meta=struct.pack(e+'I',1)+text("/'g'/'a'",e)+struct.pack(e+'IIIQI',20,68,1,2,0)
        raw=b''.join(struct.pack(e+('qQ' if big else 'Qq'),*( (s,f) if big else (f,s))) for s,f in [(-1,5),(2082844800,2**63)])
        compare(segment(meta,raw,14+(64 if big else 0),big));count+=1
    # Independent reader consumes MoonBit output in both layouts and byte orders.
    objects=[{'path':"/'g'/'a'",'type':4,'values':['-9223372036854775808','9223372036854775807']},
             {'path':"/'g'/'b'",'type':8,'values':['0','18446744073709551615']}]
    for big in [False,True]:
        for interleaved in [False,True]:
            encoded=call('encode',objects=objects,big_endian=big,interleaved=interleaved)
            compare(bytes.fromhex(encoded['hex']));count+=1
    # All writable scalar families plus Unicode/string properties, both endiannesses.
    for kind,values in [(1,['-128','127']),(2,['-32768','32767']),(3,['-2147483648','2147483647']),(4,['-9223372036854775808','9223372036854775807']),(5,['0','255']),(6,['0','65535']),(7,['0','4294967295']),(8,['0','18446744073709551615']),(9,[-1.5,3.25]),(10,['NaN','Infinity','-Infinity']),(32,['',"a'b,\n测量"]),(33,[False,True]),(68,[{'seconds':'-1','fractions':'18446744073709551615'}])]:
        for big in [False,True]:
            objects=[{'path':"/'g'/'a'",'type':kind,'values':values,'properties':[{'name':'unit_string','type':32,'value':'µV'},{'name':'serial','type':8,'value':'18446744073709551615'}]}]
            blob=bytes.fromhex(call('encode',objects=objects,big_endian=big)['hex'])
            compare(blob);count+=1
    print(json.dumps({'reference' :'npTDMS 1.10.0','cases':count,'status':'pass'}))
if __name__=='__main__':main()
