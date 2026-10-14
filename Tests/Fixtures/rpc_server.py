#!/usr/bin/env python3
"""Loopback-only fixture server. No provider connection, credentials, or real chat."""
import base64, hashlib, json, socket, struct, sys, time

mode = sys.argv[1]
listener = socket.socket()
listener.bind(('127.0.0.1', 0)); listener.listen(1); listener.settimeout(15)
print(listener.getsockname()[1], flush=True)
connection, _ = listener.accept(); connection.settimeout(15)
headers = b''
while b'\r\n\r\n' not in headers:
    headers += connection.recv(4096)
key = next(line.split(b':',1)[1].strip() for line in headers.split(b'\r\n') if line.lower().startswith(b'sec-websocket-key:'))
accept = base64.b64encode(hashlib.sha1(key + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
connection.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n\r\n')
def exact(n):
    data=b''
    while len(data)<n:
        part=connection.recv(n-len(data))
        if not part: raise EOFError()
        data+=part
    return data
def receive():
    first,second=exact(2); length=second&127
    if length==126: length=struct.unpack('!H',exact(2))[0]
    elif length==127: length=struct.unpack('!Q',exact(8))[0]
    if length>65536: raise ValueError('oversized fixture frame')
    mask=exact(4) if second&128 else b'\0'*4
    raw=exact(length)
    if first&15==8: raise EOFError()
    return json.loads(bytes(b^mask[i%4] for i,b in enumerate(raw)))
def send(obj):
    data=json.dumps(obj).encode()
    header=b'\x81'+(bytes([len(data)]) if len(data)<126 else b'\x7e'+struct.pack('!H',len(data)))
    connection.sendall(header+data)
def completed():
    send({'method':'item/completed','params':{'threadId':'fixture-chat','item':{'id':'compact-1','type':'contextCompaction'}}})
try:
    while True:
        request=receive(); method=request.get('method'); identity=request.get('id')
        if identity is None: continue
        if method=='initialize': result={'userAgent':'fixture'}
        elif method=='thread/list': result={'data':[{'id':'fixture-chat','name':'Fixture chat','status':{'type':'idle'}}]}
        elif method=='thread/read': result={'thread':{'id':'fixture-chat','status':{'type':'active' if mode=='busy' else 'idle'}}}
        elif method=='thread/compact/start':
            if request['params']['threadId']!='fixture-chat': raise ValueError('wrong target')
            if mode=='before-ack':
                completed(); send({'id':identity,'result':{}})
            else:
                send({'id':identity,'result':{}}); time.sleep(0.3); completed()
            continue
        else:
            send({'id':identity,'error':{'code':-32601,'message':'unsupported fixture method'}}); continue
        send({'id':identity,'result':result})
except (EOFError,ConnectionError,socket.timeout):
    pass
finally:
    connection.close(); listener.close()
