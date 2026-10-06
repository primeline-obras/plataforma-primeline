import {createServer} from 'node:net';
import {randomInt} from 'node:crypto';

// Windows normally allocates outgoing TCP ports in 49152–65535. PostgREST
// connects to PostgreSQL before binding HTTP, so releasing listen(0) can let
// its own outgoing connection claim the chosen HTTP port. Use a checked port
// outside that dynamic range. This changes only local test infrastructure.
export async function localPostgrestPort() {
  for (let attempt=0;attempt<100;attempt++) {
    const port=randomInt(20000,40000),server=createServer();
    const available=await new Promise((resolve,reject)=>{
      server.once('error',e=>['EADDRINUSE','EACCES'].includes(e.code)?resolve(false):reject(e));
      server.listen(port,'127.0.0.1',()=>resolve(true));
    });
    if (available) {await new Promise((resolve,reject)=>server.close(e=>e?reject(e):resolve()));return port;}
  }
  throw new Error('No available local PostgREST HTTP port outside the Windows dynamic range');
}
