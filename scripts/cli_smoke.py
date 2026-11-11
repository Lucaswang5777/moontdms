"""Public command contract and document workflows, using only Python stdlib."""
from pathlib import Path
import json, subprocess
ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / '_build/js/debug/build/cmd/main/main.js'

def request(fields, ok=True):
    result = subprocess.run(['node', str(PROGRAM), json.dumps(fields, ensure_ascii=True)],
                            cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=20)
    assert (result.returncode == 0) == ok, (result.returncode, result.stdout, result.stderr)
    body = json.loads(result.stdout)
    if ok:
        assert body['protocol'] == 'moontdms/1'
        return body['result']
    assert isinstance(body['error'], str) and body['error']

def call(op, **fields):
    return request({'protocol': 'moontdms/1', 'op': op, **fields})

def main():
    objects = [{'path': "/'g'/'voltage'", 'type': 8,
                'values': ['0', '9007199254740993', '18446744073709551615'],
                'properties': [{'name': 'wf_increment', 'type': 10, 'value': 0.5},
                               {'name': 'unit_string', 'type': 32, 'value': 'V'}]}]
    encoded = call('encode', objects=objects)['hex']
    decoded = call('decode', hex=encoded)['objects']
    assert decoded == objects
    assert len(call('inspect', hex=encoded)['segments']) == 1
    cropped = call('select', hex=encoded, paths=["/'g'/'voltage'"], start=1, end=3)['hex']
    result = call('decode', hex=cropped)['objects'][0]
    assert result['values'] == objects[0]['values'][1:]
    assert next(p for p in result['properties'] if p['name'] == 'wf_start_offset')['value'] == 0.5
    csv = call('csv', hex=cropped, waveform_time=True)['csv']
    assert '9007199254740993' in csv and '18446744073709551615' in csv
    assert csv.count('\r\n') == 3 and 'relative_time' in csv
    failures = [
        {'protocol':'other','op':'decode','hex':encoded},
        {'protocol':'moontdms/1','op':'missing'},
        {'protocol':'moontdms/1','op':'decode','hex':'0'},
        {'protocol':'moontdms/1','op':'decode','hex':'zz'},
        {'protocol':'moontdms/1','op':'select','hex':encoded,'paths':["/'g'/'missing'"]},
        {'protocol':'moontdms/1','op':'select','hex':encoded,'paths':["/'g'/'voltage'"],'end':9},
        {'protocol':'moontdms/1','op':'encode','objects':[{'path':"/'g'/'c'",'type':1,'values':['128']}]},
        {'protocol':'moontdms/1','op':'encode','objects':[{'path':"/'g'/'c'",'type':8,'values':[9007199254740993]}]},
    ]
    for fields in failures: request(fields, ok=False)
    print(json.dumps({'status':'pass', 'successful_operations':7, 'rejected_requests':len(failures)}))

if __name__ == '__main__': main()
