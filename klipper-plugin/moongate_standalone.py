"""
Moongate — single-file Moonraker component.

Deploy as:  ~/moonraker/moonraker/components/moongate.py

Registers:
  POST /server/moongate/pair    — generate a pairing code (called by MOONGATE_PAIR macro)
  POST /server/moongate/auth    — exchange a pairing code for a JWT + WireGuard config
  GET  /server/moongate/status  — check plugin status  (pass token= in args)
  GET  /server/moongate/tokens  — list active tokens   (pass token= in args)
  POST /server/moongate/revoke  — revoke a token       (pass token= in args)
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import random
import re
import string
import subprocess
import time
import uuid
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger("moonraker.moongate")

# ═══════════════════════════════════════════════════════════════════════════════
# Auth manager
# ═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR  = Path.home() / ".config" / "moongate"
TOKENS_FILE = CONFIG_DIR / "tokens.json"
SECRET_FILE = CONFIG_DIR / "secret.key"
CONFIG_FILE = CONFIG_DIR / "config.json"

DEFAULT_CONFIG = {
    "default_ttl_days":      30,
    "allow_app_override":    True,
    "pair_code_ttl_seconds": 600,
    "max_pair_attempts":     5,
    # HTTP port nginx (Moonraker's front-door) listens on.  The cloudflared
    # tunnel forwards to this port and the QR / pair-page URLs include it.
    # Default 80 matches stock KIAUH / MainsailOS; install.sh writes this
    # value when `--port N` or MOONGATE_PORT env var is used at install time.
    "http_port":             80,
}

CODE_CHARS = string.digits   # digits only → GATE-1234-5678, easy to type on phone


def _get_local_ip() -> str:
    """Return the Pi's primary LAN IP (used to embed host in the QR URL)."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "localhost"


def _get_tunnel_subdomain(tunnel_url: Optional[str]) -> Optional[str]:
    """Extract just the subdomain from a trycloudflare.com URL.
    e.g. 'https://racing-partly-mouse-surprised.trycloudflare.com' → 'racing-partly-mouse-surprised'
    """
    if not tunnel_url:
        return None
    import re
    m = re.search(r'https?://([a-z0-9-]+)\.trycloudflare\.com', tunnel_url)
    return m.group(1) if m else None


# qrcodejs 1.0.0 — inlined so the page works with no internet / strict CSP.
# Source: https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js
_QRCODE_JS = r"""var QRCode;!function(){function a(a){this.mode=c.MODE_8BIT_BYTE,this.data=a,this.parsedData=[];for(var b=[],d=0,e=this.data.length;e>d;d++){var f=this.data.charCodeAt(d);f>65536?(b[0]=240|(1835008&f)>>>18,b[1]=128|(258048&f)>>>12,b[2]=128|(4032&f)>>>6,b[3]=128|63&f):f>2048?(b[0]=224|(61440&f)>>>12,b[1]=128|(4032&f)>>>6,b[2]=128|63&f):f>128?(b[0]=192|(1984&f)>>>6,b[1]=128|63&f):b[0]=f,this.parsedData=this.parsedData.concat(b)}this.parsedData.length!=this.data.length&&(this.parsedData.unshift(191),this.parsedData.unshift(187),this.parsedData.unshift(239))}function b(a,b){this.typeNumber=a,this.errorCorrectLevel=b,this.modules=null,this.moduleCount=0,this.dataCache=null,this.dataList=[]}function i(a,b){if(void 0==a.length)throw new Error(a.length+"/"+b);for(var c=0;c<a.length&&0==a[c];)c++;this.num=new Array(a.length-c+b);for(var d=0;d<a.length-c;d++)this.num[d]=a[d+c]}function j(a,b){this.totalCount=a,this.dataCount=b}function k(){this.buffer=[],this.length=0}function m(){return"undefined"!=typeof CanvasRenderingContext2D}function n(){var a=!1,b=navigator.userAgent;return/android/i.test(b)&&(a=!0,aMat=b.toString().match(/android ([0-9]\.[0-9])/i),aMat&&aMat[1]&&(a=parseFloat(aMat[1]))),a}function r(a,b){for(var c=1,e=s(a),f=0,g=l.length;g>=f;f++){var h=0;switch(b){case d.L:h=l[f][0];break;case d.M:h=l[f][1];break;case d.Q:h=l[f][2];break;case d.H:h=l[f][3]}if(h>=e)break;c++}if(c>l.length)throw new Error("Too long data");return c}function s(a){var b=encodeURI(a).toString().replace(/\%[0-9a-fA-F]{2}/g,"a");return b.length+(b.length!=a?3:0)}a.prototype={getLength:function(){return this.parsedData.length},write:function(a){for(var b=0,c=this.parsedData.length;c>b;b++)a.put(this.parsedData[b],8)}},b.prototype={addData:function(b){var c=new a(b);this.dataList.push(c),this.dataCache=null},isDark:function(a,b){if(0>a||this.moduleCount<=a||0>b||this.moduleCount<=b)throw new Error(a+","+b);return this.modules[a][b]},getModuleCount:function(){return this.moduleCount},make:function(){this.makeImpl(!1,this.getBestMaskPattern())},makeImpl:function(a,c){this.moduleCount=4*this.typeNumber+17,this.modules=new Array(this.moduleCount);for(var d=0;d<this.moduleCount;d++){this.modules[d]=new Array(this.moduleCount);for(var e=0;e<this.moduleCount;e++)this.modules[d][e]=null}this.setupPositionProbePattern(0,0),this.setupPositionProbePattern(this.moduleCount-7,0),this.setupPositionProbePattern(0,this.moduleCount-7),this.setupPositionAdjustPattern(),this.setupTimingPattern(),this.setupTypeInfo(a,c),this.typeNumber>=7&&this.setupTypeNumber(a),null==this.dataCache&&(this.dataCache=b.createData(this.typeNumber,this.errorCorrectLevel,this.dataList)),this.mapData(this.dataCache,c)},setupPositionProbePattern:function(a,b){for(var c=-1;7>=c;c++)if(!(-1>=a+c||this.moduleCount<=a+c))for(var d=-1;7>=d;d++)-1>=b+d||this.moduleCount<=b+d||(this.modules[a+c][b+d]=c>=0&&6>=c&&(0==d||6==d)||d>=0&&6>=d&&(0==c||6==c)||c>=2&&4>=c&&d>=2&&4>=d?!0:!1)},getBestMaskPattern:function(){for(var a=0,b=0,c=0;8>c;c++){this.makeImpl(!0,c);var d=f.getLostPoint(this);(0==c||a>d)&&(a=d,b=c)}return b},createMovieClip:function(a,b,c){var d=a.createEmptyMovieClip(b,c),e=1;this.make();for(var f=0;f<this.modules.length;f++)for(var g=f*e,h=0;h<this.modules[f].length;h++){var i=h*e,j=this.modules[f][h];j&&(d.beginFill(0,100),d.moveTo(i,g),d.lineTo(i+e,g),d.lineTo(i+e,g+e),d.lineTo(i,g+e),d.endFill())}return d},setupTimingPattern:function(){for(var a=8;a<this.moduleCount-8;a++)null==this.modules[a][6]&&(this.modules[a][6]=0==a%2);for(var b=8;b<this.moduleCount-8;b++)null==this.modules[6][b]&&(this.modules[6][b]=0==b%2)},setupPositionAdjustPattern:function(){for(var a=f.getPatternPosition(this.typeNumber),b=0;b<a.length;b++)for(var c=0;c<a.length;c++){var d=a[b],e=a[c];if(null==this.modules[d][e])for(var g=-2;2>=g;g++)for(var h=-2;2>=h;h++)this.modules[d+g][e+h]=-2==g||2==g||-2==h||2==h||0==g&&0==h?!0:!1}},setupTypeNumber:function(a){for(var b=f.getBCHTypeNumber(this.typeNumber),c=0;18>c;c++){var d=!a&&1==(1&b>>c);this.modules[Math.floor(c/3)][c%3+this.moduleCount-8-3]=d}for(var c=0;18>c;c++){var d=!a&&1==(1&b>>c);this.modules[c%3+this.moduleCount-8-3][Math.floor(c/3)]=d}},setupTypeInfo:function(a,b){for(var c=this.errorCorrectLevel<<3|b,d=f.getBCHTypeInfo(c),e=0;15>e;e++){var g=!a&&1==(1&d>>e);6>e?this.modules[e][8]=g:8>e?this.modules[e+1][8]=g:this.modules[this.moduleCount-15+e][8]=g}for(var e=0;15>e;e++){var g=!a&&1==(1&d>>e);8>e?this.modules[8][this.moduleCount-e-1]=g:9>e?this.modules[8][15-e-1+1]=g:this.modules[8][15-e-1]=g}this.modules[this.moduleCount-8][8]=!a},mapData:function(a,b){for(var c=-1,d=this.moduleCount-1,e=7,g=0,h=this.moduleCount-1;h>0;h-=2)for(6==h&&h--;;){for(var i=0;2>i;i++)if(null==this.modules[d][h-i]){var j=!1;g<a.length&&(j=1==(1&a[g]>>>e));var k=f.getMask(b,d,h-i);k&&(j=!j),this.modules[d][h-i]=j,e--,-1==e&&(g++,e=7)}if(d+=c,0>d||this.moduleCount<=d){d-=c,c=-c;break}}}},b.PAD0=236,b.PAD1=17,b.createData=function(a,c,d){for(var e=j.getRSBlocks(a,c),g=new k,h=0;h<d.length;h++){var i=d[h];g.put(i.mode,4),g.put(i.getLength(),f.getLengthInBits(i.mode,a)),i.write(g)}for(var l=0,h=0;h<e.length;h++)l+=e[h].dataCount;if(g.getLengthInBits()>8*l)throw new Error("code length overflow. ("+g.getLengthInBits()+">"+8*l+")");for(g.getLengthInBits()+4<=8*l&&g.put(0,4);0!=g.getLengthInBits()%8;)g.putBit(!1);for(;;){if(g.getLengthInBits()>=8*l)break;if(g.put(b.PAD0,8),g.getLengthInBits()>=8*l)break;g.put(b.PAD1,8)}return b.createBytes(g,e)},b.createBytes=function(a,b){for(var c=0,d=0,e=0,g=new Array(b.length),h=new Array(b.length),j=0;j<b.length;j++){var k=b[j].dataCount,l=b[j].totalCount-k;d=Math.max(d,k),e=Math.max(e,l),g[j]=new Array(k);for(var m=0;m<g[j].length;m++)g[j][m]=255&a.buffer[m+c];c+=k;var n=f.getErrorCorrectPolynomial(l),o=new i(g[j],n.getLength()-1),p=o.mod(n);h[j]=new Array(n.getLength()-1);for(var m=0;m<h[j].length;m++){var q=m+p.getLength()-h[j].length;h[j][m]=q>=0?p.get(q):0}}for(var r=0,m=0;m<b.length;m++)r+=b[m].totalCount;for(var s=new Array(r),t=0,m=0;d>m;m++)for(var j=0;j<b.length;j++)m<g[j].length&&(s[t++]=g[j][m]);for(var m=0;e>m;m++)for(var j=0;j<b.length;j++)m<h[j].length&&(s[t++]=h[j][m]);return s};for(var c={MODE_NUMBER:1,MODE_ALPHA_NUM:2,MODE_8BIT_BYTE:4,MODE_KANJI:8},d={L:1,M:0,Q:3,H:2},e={PATTERN000:0,PATTERN001:1,PATTERN010:2,PATTERN011:3,PATTERN100:4,PATTERN101:5,PATTERN110:6,PATTERN111:7},f={PATTERN_POSITION_TABLE:[[],[6,18],[6,22],[6,26],[6,30],[6,34],[6,22,38],[6,24,42],[6,26,46],[6,28,50],[6,30,54],[6,32,58],[6,34,62],[6,26,46,66],[6,26,48,70],[6,26,50,74],[6,30,54,78],[6,30,56,82],[6,30,58,86],[6,34,62,90],[6,28,50,72,94],[6,26,50,74,98],[6,30,54,78,102],[6,28,54,80,106],[6,32,58,84,110],[6,30,58,86,114],[6,34,62,90,118],[6,26,50,74,98,122],[6,30,54,78,102,126],[6,26,52,78,104,130],[6,30,56,82,108,134],[6,34,60,86,112,138],[6,30,58,86,114,142],[6,34,62,90,118,146],[6,30,54,78,102,126,150],[6,24,50,76,102,128,154],[6,28,54,80,106,132,158],[6,32,58,84,110,136,162],[6,26,54,82,110,138,166],[6,30,58,86,114,142,170]],G15:1335,G18:7973,G15_MASK:21522,getBCHTypeInfo:function(a){for(var b=a<<10;f.getBCHDigit(b)-f.getBCHDigit(f.G15)>=0;)b^=f.G15<<f.getBCHDigit(b)-f.getBCHDigit(f.G15);return(a<<10|b)^f.G15_MASK},getBCHTypeNumber:function(a){for(var b=a<<12;f.getBCHDigit(b)-f.getBCHDigit(f.G18)>=0;)b^=f.G18<<f.getBCHDigit(b)-f.getBCHDigit(f.G18);return a<<12|b},getBCHDigit:function(a){for(var b=0;0!=a;)b++,a>>>=1;return b},getPatternPosition:function(a){return f.PATTERN_POSITION_TABLE[a-1]},getMask:function(a,b,c){switch(a){case e.PATTERN000:return 0==(b+c)%2;case e.PATTERN001:return 0==b%2;case e.PATTERN010:return 0==c%3;case e.PATTERN011:return 0==(b+c)%3;case e.PATTERN100:return 0==(Math.floor(b/2)+Math.floor(c/3))%2;case e.PATTERN101:return 0==b*c%2+b*c%3;case e.PATTERN110:return 0==(b*c%2+b*c%3)%2;case e.PATTERN111:return 0==(b*c%3+(b+c)%2)%2;default:throw new Error("bad maskPattern:"+a)}},getErrorCorrectPolynomial:function(a){for(var b=new i([1],0),c=0;a>c;c++)b=b.multiply(new i([1,g.gexp(c)],0));return b},getLengthInBits:function(a,b){if(b>=1&&10>b)switch(a){case c.MODE_NUMBER:return 10;case c.MODE_ALPHA_NUM:return 9;case c.MODE_8BIT_BYTE:return 8;case c.MODE_KANJI:return 8;default:throw new Error("mode:"+a)}else if(27>b)switch(a){case c.MODE_NUMBER:return 12;case c.MODE_ALPHA_NUM:return 11;case c.MODE_8BIT_BYTE:return 16;case c.MODE_KANJI:return 10;default:throw new Error("mode:"+a)}else{if(!(41>b))throw new Error("type:"+b);switch(a){case c.MODE_NUMBER:return 14;case c.MODE_ALPHA_NUM:return 13;case c.MODE_8BIT_BYTE:return 16;case c.MODE_KANJI:return 12;default:throw new Error("mode:"+a)}}},getLostPoint:function(a){for(var b=a.getModuleCount(),c=0,d=0;b>d;d++)for(var e=0;b>e;e++){for(var f=0,g=a.isDark(d,e),h=-1;1>=h;h++)if(!(0>d+h||d+h>=b))for(var i=-1;1>=i;i++)0>e+i||e+i>=b||(0!=h||0!=i)&&g==a.isDark(d+h,e+i)&&f++;f>5&&(c+=3+f-5)}for(var d=0;b-1>d;d++)for(var e=0;b-1>e;e++){var j=0;a.isDark(d,e)&&j++,a.isDark(d+1,e)&&j++,a.isDark(d,e+1)&&j++,a.isDark(d+1,e+1)&&j++,(0==j||4==j)&&(c+=3)}for(var d=0;b>d;d++)for(var e=0;b-6>e;e++)a.isDark(d,e)&&!a.isDark(d,e+1)&&a.isDark(d,e+2)&&a.isDark(d,e+3)&&a.isDark(d,e+4)&&!a.isDark(d,e+5)&&a.isDark(d,e+6)&&(c+=40);for(var e=0;b>e;e++)for(var d=0;b-6>d;d++)a.isDark(d,e)&&!a.isDark(d+1,e)&&a.isDark(d+2,e)&&a.isDark(d+3,e)&&a.isDark(d+4,e)&&!a.isDark(d+5,e)&&a.isDark(d+6,e)&&(c+=40);for(var k=0,e=0;b>e;e++)for(var d=0;b>d;d++)a.isDark(d,e)&&k++;var l=Math.abs(100*k/b/b-50)/5;return c+=10*l}},g={glog:function(a){if(1>a)throw new Error("glog("+a+")");return g.LOG_TABLE[a]},gexp:function(a){for(;0>a;)a+=255;for(;a>=256;)a-=255;return g.EXP_TABLE[a]},EXP_TABLE:new Array(256),LOG_TABLE:new Array(256)},h=0;8>h;h++)g.EXP_TABLE[h]=1<<h;for(var h=8;256>h;h++)g.EXP_TABLE[h]=g.EXP_TABLE[h-4]^g.EXP_TABLE[h-5]^g.EXP_TABLE[h-6]^g.EXP_TABLE[h-8];for(var h=0;255>h;h++)g.LOG_TABLE[g.EXP_TABLE[h]]=h;i.prototype={get:function(a){return this.num[a]},getLength:function(){return this.num.length},multiply:function(a){for(var b=new Array(this.getLength()+a.getLength()-1),c=0;c<this.getLength();c++)for(var d=0;d<a.getLength();d++)b[c+d]^=g.gexp(g.glog(this.get(c))+g.glog(a.get(d)));return new i(b,0)},mod:function(a){if(this.getLength()-a.getLength()<0)return this;for(var b=g.glog(this.get(0))-g.glog(a.get(0)),c=new Array(this.getLength()),d=0;d<this.getLength();d++)c[d]=this.get(d);for(var d=0;d<a.getLength();d++)c[d]^=g.gexp(g.glog(a.get(d))+b);return new i(c,0).mod(a)}},j.RS_BLOCK_TABLE=[[1,26,19],[1,26,16],[1,26,13],[1,26,9],[1,44,34],[1,44,28],[1,44,22],[1,44,16],[1,70,55],[1,70,44],[2,35,17],[2,35,13],[1,100,80],[2,50,32],[2,50,24],[4,25,9],[1,134,108],[2,67,43],[2,33,15,2,34,16],[2,33,11,2,34,12],[2,86,68],[4,43,27],[4,43,19],[4,43,15],[2,98,78],[4,49,31],[2,32,14,4,33,15],[4,39,13,1,40,14],[2,121,97],[2,60,38,2,61,39],[4,40,18,4,41,19],[4,40,14,2,41,15],[2,146,116],[3,58,36,2,59,37],[4,36,16,4,37,17],[4,36,12,4,37,13],[2,86,68,2,87,69],[4,69,43,1,70,44],[6,43,19,2,44,20],[6,43,15,2,44,16],[4,101,81],[1,80,50,4,81,51],[4,50,22,4,51,23],[3,36,12,8,37,13],[2,116,92,2,117,93],[6,58,36,2,59,37],[4,46,20,6,47,21],[7,42,14,4,43,15],[4,133,107],[8,59,37,1,60,38],[8,44,20,4,45,21],[12,33,11,4,34,12],[3,145,115,1,146,116],[4,64,40,5,65,41],[11,36,16,5,37,17],[11,36,12,5,37,13],[5,109,87,1,110,88],[5,65,41,5,66,42],[5,54,24,7,55,25],[11,36,12],[5,122,98,1,123,99],[7,73,45,3,74,46],[15,43,19,2,44,20],[3,45,15,13,46,16],[1,135,107,5,136,108],[10,74,46,1,75,47],[1,50,22,15,51,23],[2,42,14,17,43,15],[5,150,120,1,151,121],[9,69,43,4,70,44],[17,50,22,1,51,23],[2,42,14,19,43,15],[3,141,113,4,142,114],[3,70,44,11,71,45],[17,47,21,4,48,22],[9,39,13,16,40,14],[3,135,107,5,136,108],[3,67,41,13,68,42],[15,54,24,5,55,25],[15,43,15,10,44,16],[4,144,116,4,145,117],[17,68,42],[17,50,22,6,51,23],[19,46,16,6,47,17],[2,139,111,7,140,112],[17,74,46],[7,54,24,16,55,25],[34,37,13],[4,151,121,5,152,122],[4,75,47,14,76,48],[11,54,24,14,55,25],[16,45,15,14,46,16],[6,147,117,4,148,118],[6,73,45,14,74,46],[11,54,24,16,55,25],[30,46,16,2,47,17],[8,132,106,4,133,107],[8,75,47,13,76,48],[7,54,24,22,55,25],[22,45,15,13,46,16],[10,142,114,2,143,115],[19,74,46,4,75,47],[28,50,22,6,51,23],[33,46,16,4,47,17],[8,152,122,4,153,123],[22,73,45,3,74,46],[8,53,23,26,54,24],[12,45,15,28,46,16],[3,147,117,10,148,118],[3,73,45,23,74,46],[4,54,24,31,55,25],[11,45,15,31,46,16],[7,146,116,7,147,117],[21,73,45,7,74,46],[1,53,23,37,54,24],[19,45,15,26,46,16],[5,145,115,10,146,116],[19,75,47,10,76,48],[15,54,24,25,55,25],[23,45,15,25,46,16],[13,145,115,3,146,116],[2,74,46,29,75,47],[42,54,24,1,55,25],[23,45,15,28,46,16],[17,145,115],[10,74,46,23,75,47],[10,54,24,35,55,25],[19,45,15,35,46,16],[17,145,115,1,146,116],[14,74,46,21,75,47],[29,54,24,19,55,25],[11,45,15,46,46,16],[13,145,115,6,146,116],[14,74,46,23,75,47],[44,54,24,7,55,25],[59,46,16,1,47,17],[12,151,121,7,152,122],[12,75,47,26,76,48],[39,54,24,14,55,25],[22,45,15,41,46,16],[6,151,121,14,152,122],[6,75,47,34,76,48],[46,54,24,10,55,25],[2,45,15,64,46,16],[17,152,122,4,153,123],[29,74,46,14,75,47],[49,54,24,10,55,25],[24,45,15,46,46,16],[4,152,122,18,153,123],[13,74,46,32,75,47],[48,54,24,14,55,25],[42,45,15,32,46,16],[20,147,117,4,148,118],[40,75,47,7,76,48],[43,54,24,22,55,25],[10,45,15,67,46,16],[19,148,118,6,149,119],[18,75,47,31,76,48],[34,54,24,34,55,25],[20,45,15,61,46,16]],j.getRSBlocks=function(a,b){var c=j.getRsBlockTable(a,b);if(void 0==c)throw new Error("bad rs block @ typeNumber:"+a+"/errorCorrectLevel:"+b);for(var d=c.length/3,e=[],f=0;d>f;f++)for(var g=c[3*f+0],h=c[3*f+1],i=c[3*f+2],k=0;g>k;k++)e.push(new j(h,i));return e},j.getRsBlockTable=function(a,b){switch(b){case d.L:return j.RS_BLOCK_TABLE[4*(a-1)+0];case d.M:return j.RS_BLOCK_TABLE[4*(a-1)+1];case d.Q:return j.RS_BLOCK_TABLE[4*(a-1)+2];case d.H:return j.RS_BLOCK_TABLE[4*(a-1)+3];default:return void 0}},k.prototype={get:function(a){var b=Math.floor(a/8);return 1==(1&this.buffer[b]>>>7-a%8)},put:function(a,b){for(var c=0;b>c;c++)this.putBit(1==(1&a>>>b-c-1))},getLengthInBits:function(){return this.length},putBit:function(a){var b=Math.floor(this.length/8);this.buffer.length<=b&&this.buffer.push(0),a&&(this.buffer[b]|=128>>>this.length%8),this.length++}};var l=[[17,14,11,7],[32,26,20,14],[53,42,32,24],[78,62,46,34],[106,84,60,44],[134,106,74,58],[154,122,86,64],[192,152,108,84],[230,180,130,98],[271,213,151,119],[321,251,177,137],[367,287,203,155],[425,331,241,177],[458,362,258,194],[520,412,292,220],[586,450,322,250],[644,504,364,280],[718,560,394,310],[792,624,442,338],[858,666,482,382],[929,711,509,403],[1003,779,565,439],[1091,857,611,461],[1171,911,661,511],[1273,997,715,535],[1367,1059,751,593],[1465,1125,805,625],[1528,1190,868,658],[1628,1264,908,698],[1732,1370,982,742],[1840,1452,1030,790],[1952,1538,1112,842],[2068,1628,1168,898],[2188,1722,1228,958],[2303,1809,1283,983],[2431,1911,1351,1051],[2563,1989,1423,1093],[2699,2099,1499,1139],[2809,2213,1579,1219],[2953,2331,1663,1273]],o=function(){var a=function(a,b){this._el=a,this._htOption=b};return a.prototype.draw=function(a){function g(a,b){var c=document.createElementNS("http://www.w3.org/2000/svg",a);for(var d in b)b.hasOwnProperty(d)&&c.setAttribute(d,b[d]);return c}var b=this._htOption,c=this._el,d=a.getModuleCount();Math.floor(b.width/d),Math.floor(b.height/d),this.clear();var h=g("svg",{viewBox:"0 0 "+String(d)+" "+String(d),width:"100%",height:"100%",fill:b.colorLight});h.setAttributeNS("http://www.w3.org/2000/xmlns/","xmlns:xlink","http://www.w3.org/1999/xlink"),c.appendChild(h),h.appendChild(g("rect",{fill:b.colorDark,width:"1",height:"1",id:"template"}));for(var i=0;d>i;i++)for(var j=0;d>j;j++)if(a.isDark(i,j)){var k=g("use",{x:String(i),y:String(j)});k.setAttributeNS("http://www.w3.org/1999/xlink","href","#template"),h.appendChild(k)}},a.prototype.clear=function(){for(;this._el.hasChildNodes();)this._el.removeChild(this._el.lastChild)},a}(),p="svg"===document.documentElement.tagName.toLowerCase(),q=p?o:m()?function(){function a(){this._elImage.src=this._elCanvas.toDataURL("image/png"),this._elImage.style.display="block",this._elCanvas.style.display="none"}function d(a,b){var c=this;if(c._fFail=b,c._fSuccess=a,null===c._bSupportDataURI){var d=document.createElement("img"),e=function(){c._bSupportDataURI=!1,c._fFail&&_fFail.call(c)},f=function(){c._bSupportDataURI=!0,c._fSuccess&&c._fSuccess.call(c)};return d.onabort=e,d.onerror=e,d.onload=f,d.src="data:image/gif;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==",void 0}c._bSupportDataURI===!0&&c._fSuccess?c._fSuccess.call(c):c._bSupportDataURI===!1&&c._fFail&&c._fFail.call(c)}if(this._android&&this._android<=2.1){var b=1/window.devicePixelRatio,c=CanvasRenderingContext2D.prototype.drawImage;CanvasRenderingContext2D.prototype.drawImage=function(a,d,e,f,g,h,i,j){if("nodeName"in a&&/img/i.test(a.nodeName))for(var l=arguments.length-1;l>=1;l--)arguments[l]=arguments[l]*b;else"undefined"==typeof j&&(arguments[1]*=b,arguments[2]*=b,arguments[3]*=b,arguments[4]*=b);c.apply(this,arguments)}}var e=function(a,b){this._bIsPainted=!1,this._android=n(),this._htOption=b,this._elCanvas=document.createElement("canvas"),this._elCanvas.width=b.width,this._elCanvas.height=b.height,a.appendChild(this._elCanvas),this._el=a,this._oContext=this._elCanvas.getContext("2d"),this._bIsPainted=!1,this._elImage=document.createElement("img"),this._elImage.style.display="none",this._el.appendChild(this._elImage),this._bSupportDataURI=null};return e.prototype.draw=function(a){var b=this._elImage,c=this._oContext,d=this._htOption,e=a.getModuleCount(),f=d.width/e,g=d.height/e,h=Math.round(f),i=Math.round(g);b.style.display="none",this.clear();for(var j=0;e>j;j++)for(var k=0;e>k;k++){var l=a.isDark(j,k),m=k*f,n=j*g;c.strokeStyle=l?d.colorDark:d.colorLight,c.lineWidth=1,c.fillStyle=l?d.colorDark:d.colorLight,c.fillRect(m,n,f,g),c.strokeRect(Math.floor(m)+.5,Math.floor(n)+.5,h,i),c.strokeRect(Math.ceil(m)-.5,Math.ceil(n)-.5,h,i)}this._bIsPainted=!0},e.prototype.makeImage=function(){this._bIsPainted&&d.call(this,a)},e.prototype.isPainted=function(){return this._bIsPainted},e.prototype.clear=function(){this._oContext.clearRect(0,0,this._elCanvas.width,this._elCanvas.height),this._bIsPainted=!1},e.prototype.round=function(a){return a?Math.floor(1e3*a)/1e3:a},e}():function(){var a=function(a,b){this._el=a,this._htOption=b};return a.prototype.draw=function(a){for(var b=this._htOption,c=this._el,d=a.getModuleCount(),e=Math.floor(b.width/d),f=Math.floor(b.height/d),g=['<table style="border:0;border-collapse:collapse;">'],h=0;d>h;h++){g.push("<tr>");for(var i=0;d>i;i++)g.push('<td style="border:0;border-collapse:collapse;padding:0;margin:0;width:'+e+"px;height:"+f+"px;background-color:"+(a.isDark(h,i)?b.colorDark:b.colorLight)+';"></td>');g.push("</tr>")}g.push("</table>"),c.innerHTML=g.join("");var j=c.childNodes[0],k=(b.width-j.offsetWidth)/2,l=(b.height-j.offsetHeight)/2;k>0&&l>0&&(j.style.margin=l+"px "+k+"px")},a.prototype.clear=function(){this._el.innerHTML=""},a}();QRCode=function(a,b){if(this._htOption={width:256,height:256,typeNumber:4,colorDark:"#000000",colorLight:"#ffffff",correctLevel:d.H},"string"==typeof b&&(b={text:b}),b)for(var c in b)this._htOption[c]=b[c];"string"==typeof a&&(a=document.getElementById(a)),this._android=n(),this._el=a,this._oQRCode=null,this._oDrawing=new q(this._el,this._htOption),this._htOption.text&&this.makeCode(this._htOption.text)},QRCode.prototype.makeCode=function(a){this._oQRCode=new b(r(a,this._htOption.correctLevel),this._htOption.correctLevel),this._oQRCode.addData(a),this._oQRCode.make(),this._el.title=a,this._oDrawing.draw(this._oQRCode),this.makeImage()},QRCode.prototype.makeImage=function(){"function"==typeof this._oDrawing.makeImage&&(!this._android||this._android>=3)&&this._oDrawing.makeImage()},QRCode.prototype.clear=function(){this._oDrawing.clear()},QRCode.CorrectLevel=d}();"""

_PAIR_PAGE_HTML = """\
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moongate Pairing</title>
<style>
  body {{ font-family: system-ui, sans-serif; max-width: 420px; margin: 40px auto;
          padding: 20px; text-align: center; background: #111827; color: #e5e7eb; }}
  h1   {{ color: #60a5fa; margin-bottom: 4px; }}
  p    {{ color: #9ca3af; margin-top: 0; }}
  #qr  {{ margin: 24px auto; display: inline-block; background: #fff;
          padding: 12px; border-radius: 12px; }}
  .btn {{ display: inline-block; background: #3b82f6; color: #fff;
          padding: 14px 28px; border-radius: 8px; text-decoration: none;
          font-size: 16px; margin: 10px 0; font-weight: 600; }}
  .btn:hover {{ background: #2563eb; }}
  small {{ color: #6b7280; font-size: 13px; }}
  #status {{ color: #f87171; }}
</style>
</head>
<body>
<h1>&#127769; Moongate</h1>
<p>Scan with the Moongate app to pair your printer.</p>
<div id="qr"><span id="status">Loading&hellip;</span></div>
<div id="actions" style="display:none">
  <br>
  <a id="open-app" class="btn" href="#">Open in Moongate App</a>
  <br>
  <small>Code expires in 10&thinsp;min &mdash; re-run MOONGATE_PAIR to refresh.</small>
</div>
<script>__QRCODE_JS__</script>
<script>
(async function load() {{
  try {{
    const r = await fetch('/server/moongate/qr');
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const d   = await r.json();
    const url = (d.result || d).qr_url;
    if (!url) throw new Error('No active pairing session');
    document.getElementById('status').textContent = '';
    new QRCode(document.getElementById('qr'), {{
      text: url, width: 240, height: 240,
      colorDark: '#000000', colorLight: '#ffffff',
    }});
    document.getElementById('open-app').href = url;
    document.getElementById('actions').style.display = '';
  }} catch(e) {{
    document.getElementById('status').textContent =
      'Error: ' + e.message + '. Run MOONGATE_PAIR in Klipper console first.';
  }}
}})();
</script>
</body>
</html>
"""

# Directories to try when writing the static pair page.
# Listed most-specific first; first writable path wins.
_WEBROOT_CANDIDATES = [
    Path("/home/pi/printer_data/www"),
    Path("/home/pi/mainsail"),
    Path("/home/pi/fluidd"),
    Path("/var/www/html"),
]


def _write_pair_page() -> Optional[Path]:
    """Write moongate-pair.html to the first writable web-root we find."""
    for directory in _WEBROOT_CANDIDATES:
        if directory.is_dir():
            target = directory / "moongate-pair.html"
            try:
                # 1. Collapse Python format-string {{ / }} escapes to single braces.
                # 2. Splice in the inlined QR library (stored as a raw string so
                #    its own braces don't need escaping).
                html = _PAIR_PAGE_HTML.replace('{{', '{').replace('}}', '}')
                html = html.replace('__QRCODE_JS__', _QRCODE_JS)
                target.write_text(html)
                return target
            except OSError:
                continue
    return None


def _get_tunnel_url() -> Optional[str]:
    """
    Return the active Cloudflare quick-tunnel URL, or None if cloudflared
    is not running / not yet ready.

    Detection order (most-reliable first):
      1. cloudflared local REST API (/quicktunnel on port 20241 or 2000)
         — always returns the live URL, immune to log rotation or staleness.
      2. Log file (stdout captured by systemd) — uses LAST match so URL
         rotation after a cloudflared reconnect gives the current URL, not
         the original one.
      3. journalctl — last match, tries moongate-tunnel then cloudflared.
    """
    import subprocess
    import urllib.request

    pattern = re.compile(r'https://[a-z0-9-]+\.trycloudflare\.com')

    # Strategy 1: cloudflared local REST API — live URL, no staleness risk.
    # cloudflared v2023+ exposes GET /quicktunnel → {"hostname":"…","port":…}
    # The metrics server listens on 20241 (recent) or 2000 (older builds).
    for port in (20241, 2000):
        for path in ('/quicktunnel', '/metrics', '/'):
            try:
                with urllib.request.urlopen(
                    f'http://localhost:{port}{path}', timeout=2
                ) as resp:
                    body = resp.read().decode(errors='replace')
                    m = pattern.search(body)
                    if m:
                        return m.group(0)
            except Exception:
                pass

    # Strategy 2: log file — LAST match handles URL rotation after reconnects.
    for p in (Path('/run/moongate-tunnel.log'), Path('/tmp/moongate-tunnel.log')):
        if p.exists():
            try:
                matches = pattern.findall(p.read_text())
                if matches:
                    return matches[-1]
            except Exception:
                pass

    # Strategy 3: journalctl — last match, try both known unit names.
    for unit in ('moongate-tunnel', 'cloudflared'):
        try:
            result = subprocess.run(
                ['journalctl', '-u', unit, '--no-pager', '-n', '500'],
                capture_output=True, text=True, timeout=5,
            )
            matches = pattern.findall(result.stdout)
            if matches:
                return matches[-1]
        except Exception:
            pass

    return None


@dataclass
class DeviceToken:
    token_id:    str
    device_name: str
    issued_at:   float
    expires_at:  Optional[float]
    last_seen:   float
    revoked:     bool = False
    # Provisional tokens are issued by MOONGATE_PAIR with a short initial TTL
    # (e.g. 10 min) on the device-token record, even though the JWT itself
    # is signed for the full 30 days.  The first time a provisional token is
    # actually used, [AuthManager.validate_token] "promotes" it — the TTL on
    # this record extends to match the JWT's exp claim.  If the token is
    # never used, the record expires inside the short window and the token
    # becomes invalid even though the signed JWT would otherwise still
    # validate.  This closes the "shared pair URL but nobody paired with it"
    # leak window from 30 days to 10 minutes.
    provisional: bool = False

    def is_valid(self) -> bool:
        if self.revoked:
            return False
        if self.expires_at is not None and time.time() > self.expires_at:
            return False
        return True


@dataclass
class PairingCode:
    code:       str
    created_at: float
    expires_at: float
    attempts:   int  = 0
    used:       bool = False

    def is_valid(self) -> bool:
        return not self.used and self.attempts < 5 and time.time() < self.expires_at


def _b64(data: bytes) -> str:
    import base64
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class AuthManager:
    def __init__(self) -> None:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self._config         = self._load_config()
        self._secret         = self._load_or_create_secret()
        self._tokens:        dict[str, DeviceToken] = {}
        self._pending_codes: dict[str, PairingCode] = {}
        self._load_tokens()

    @property
    def http_port(self) -> int:
        """The HTTP port nginx serves on (default 80; install.sh writes the
        configured value when `--port N` was used)."""
        try:
            return int(self._config.get("http_port", 80))
        except (TypeError, ValueError):
            return 80

    def generate_pair_code(self) -> tuple[str, str]:
        """Return (display_code, qr_payload). Format: GATE-XXXX-XXXX."""
        self._sweep_expired_codes()
        part1   = "".join(random.choices(CODE_CHARS, k=4))
        part2   = "".join(random.choices(CODE_CHARS, k=4))
        display = f"GATE-{part1}-{part2}"
        raw     = f"{part1}{part2}"
        ttl     = self._config["pair_code_ttl_seconds"]
        now     = time.time()
        self._pending_codes[raw] = PairingCode(
            code=raw, created_at=now, expires_at=now + ttl
        )
        logger.info("Pairing code generated (expires in %ds)", ttl)
        return display, f"moongate://pair?code={display}"

    def issue_direct_token(
        self,
        device_name: str = "Paired via QR",
        ttl_days: Optional[int] = None,
        provisional: bool = False,
    ) -> tuple[str, str]:
        """
        Pre-issue a JWT without requiring a code exchange.
        Used for QR-based pairing where the phone may not have direct
        network access to the Pi (e.g. WiFi AP isolation).

        When `provisional=True`, the device-token record gets a short initial
        TTL (`provisional_ttl_seconds`, default 10 min).  The JWT itself is
        still signed with the full TTL, so a successful first-use promotion
        in [validate_token] doesn't require re-issuing the JWT — it just
        extends the device-token record's `expires_at` to match.  If the
        token is never used, the record expires inside the short window and
        the token becomes invalid even though the JWT would otherwise still
        validate.  This is the defence against a shared-pair-URL leak.

        Returns (jwt, token_id).
        """
        if ttl_days is None:
            ttl_days = self._config["default_ttl_days"]
        token_id        = str(uuid.uuid4())
        now             = time.time()
        full_expires_at = (now + ttl_days * 86400) if ttl_days else None

        if provisional:
            short_ttl_sec   = self._config.get("provisional_ttl_seconds", 600)
            record_expires  = now + short_ttl_sec
        else:
            record_expires  = full_expires_at

        token = DeviceToken(
            token_id=token_id, device_name=device_name,
            issued_at=now, expires_at=record_expires, last_seen=now,
            provisional=provisional,
        )
        self._tokens[token_id] = token
        self._save_tokens()
        # JWT signed with the FULL TTL so promotion doesn't need a re-issue
        jwt = self._sign_token(token_id, full_expires_at)
        logger.info(
            "Direct (QR) token issued for '%s' (id=%s%s)",
            device_name, token_id,
            ", provisional 10-min TTL" if provisional else "",
        )
        return jwt, token_id

    def exchange_code(
        self,
        raw_code: str,
        device_name: str,
        requested_ttl_days: Optional[int] = None,
    ) -> Optional[tuple[str, str]]:
        """Validate code → (jwt, token_id) or None."""
        # Accept "GATE-1234-5678", "1234-5678", or "12345678"
        normalized = raw_code.upper().replace("-", "").replace("GATE", "")
        entry = self._pending_codes.get(normalized)

        if entry is None or not entry.is_valid():
            if entry:
                entry.attempts += 1
                self._save_tokens()
            logger.warning("Invalid or expired pairing code attempt")
            return None

        entry.used = True
        token_id   = str(uuid.uuid4())
        ttl_days   = self._config["default_ttl_days"]
        if requested_ttl_days is not None and self._config["allow_app_override"]:
            ttl_days = requested_ttl_days

        now        = time.time()
        expires_at = (now + ttl_days * 86400) if ttl_days is not None else None

        token = DeviceToken(
            token_id=token_id, device_name=device_name,
            issued_at=now, expires_at=expires_at, last_seen=now,
        )
        self._tokens[token_id] = token
        self._save_tokens()

        jwt = self._sign_token(token_id, expires_at)
        logger.info("Token issued for '%s' (id=%s)", device_name, token_id)
        return jwt, token_id

    def validate_token(self, jwt: str) -> Optional[str]:
        token_id = self._verify_token(jwt)
        if token_id is None:
            return None
        token = self._tokens.get(token_id)
        if token is None or not token.is_valid():
            return None

        # Provisional → active.  First successful validate extends the device-
        # token record's expires_at from the short provisional TTL to the
        # full default TTL (matching what the JWT was already signed for).
        if token.provisional:
            default_ttl = self._config["default_ttl_days"]
            token.expires_at = (
                time.time() + default_ttl * 86400 if default_ttl else None
            )
            token.provisional = False
            logger.info(
                "Promoted provisional token to full TTL: id=%s name='%s'",
                token_id, token.device_name,
            )

        token.last_seen = time.time()
        self._save_tokens()
        return token_id

    def revoke_token(self, token_id: str) -> bool:
        token = self._tokens.get(token_id)
        if token is None:
            return False
        token.revoked = True
        self._save_tokens()
        logger.info("Token revoked: %s", token_id)
        return True

    def revoke_all_tokens(self) -> int:
        """Revoke every active token.  Returns the count of newly-revoked
        tokens (already-revoked tokens aren't double-counted).  Called by
        the MOONGATE_REVOKE_ALL Klipper macro for incident response — e.g.
        when the user has shared the tunnel URL with someone and wants to
        invalidate everyone in one shot."""
        count = 0
        for token in self._tokens.values():
            if not token.revoked:
                token.revoked = True
                count += 1
        if count > 0:
            self._save_tokens()
        logger.info("Revoke-all: %d active tokens revoked", count)
        return count

    def list_tokens(self) -> list[dict]:
        return [{**asdict(t), "valid": t.is_valid()} for t in self._tokens.values()]

    # ── JWT (minimal HS256, no external deps) ─────────────────────────────────

    def _sign_token(self, token_id: str, expires_at: Optional[float]) -> str:
        header  = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
        payload = _b64(json.dumps({
            "sub": token_id,
            "iat": int(time.time()),
            **({"exp": int(expires_at)} if expires_at else {}),
        }).encode())
        sig = _b64(
            hmac.new(
                self._secret,
                f"{header}.{payload}".encode(),
                hashlib.sha256,
            ).digest()
        )
        return f"{header}.{payload}.{sig}"

    def _verify_token(self, jwt: str) -> Optional[str]:
        import base64
        try:
            header, payload, sig = jwt.split(".")
            expected = _b64(
                hmac.new(
                    self._secret,
                    f"{header}.{payload}".encode(),
                    hashlib.sha256,
                ).digest()
            )
            if not hmac.compare_digest(sig, expected):
                return None
            claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
            exp = claims.get("exp")
            if exp and time.time() > exp:
                return None
            return claims["sub"]
        except Exception:
            return None

    # ── Persistence ───────────────────────────────────────────────────────────

    def _load_config(self) -> dict:
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    return {**DEFAULT_CONFIG, **json.load(f)}
            except Exception:
                pass
        return DEFAULT_CONFIG.copy()

    def _load_or_create_secret(self) -> bytes:
        if SECRET_FILE.exists():
            return SECRET_FILE.read_bytes()
        secret = os.urandom(32)
        SECRET_FILE.write_bytes(secret)
        SECRET_FILE.chmod(0o600)
        logger.info("New Moongate secret key created at %s", SECRET_FILE)
        return secret

    def _load_tokens(self) -> None:
        if not TOKENS_FILE.exists():
            return
        try:
            with open(TOKENS_FILE) as f:
                data = json.load(f)
            for raw in data.get("tokens", []):
                t = DeviceToken(**raw)
                self._tokens[t.token_id] = t
        except Exception as e:
            logger.error("Failed to load tokens: %s", e)

    def _save_tokens(self) -> None:
        try:
            with open(TOKENS_FILE, "w") as f:
                json.dump(
                    {"tokens": [asdict(t) for t in self._tokens.values()]},
                    f, indent=2,
                )
        except Exception as e:
            logger.error("Failed to save tokens: %s", e)

    def _sweep_expired_codes(self) -> None:
        now = time.time()
        self._pending_codes = {
            k: v for k, v in self._pending_codes.items() if now < v.expires_at
        }


# ═══════════════════════════════════════════════════════════════════════════════
# WireGuard manager
# ═══════════════════════════════════════════════════════════════════════════════

WG_IFACE      = "wg0"
WG_CONF       = f"/etc/wireguard/{WG_IFACE}.conf"
WG_PUB_KEY    = "/etc/wireguard/server_public.key"
VPN_SUBNET    = "10.13.13"
SERVER_VPN_IP = f"{VPN_SUBNET}.1"
PEERS_DB      = Path.home() / ".config" / "moongate" / "peers.json"


class WireGuardManager:
    def __init__(self) -> None:
        PEERS_DB.parent.mkdir(parents=True, exist_ok=True)
        self._peers: dict[str, dict] = self._load_peers()

    def server_public_key(self) -> Optional[str]:
        try:
            return Path(WG_PUB_KEY).read_text().strip()
        except FileNotFoundError:
            return None

    def endpoint(self, configured: Optional[str]) -> Optional[str]:
        if configured:
            ep = configured.strip()
            if ep and ":" not in ep:
                ep = f"{ep}:51820"
            return ep or None
        try:
            result = subprocess.run(
                ["hostname", "-I"], capture_output=True, text=True, timeout=5
            )
            ip = result.stdout.strip().split()[0]
            return f"{ip}:51820"
        except Exception:
            return None

    def add_peer(self, device_id: str, phone_pubkey: str) -> Optional[dict]:
        if self.server_public_key() is None:
            return None
        used   = {p["vpn_ip"] for p in self._peers.values()}
        vpn_ip = None
        for i in range(2, 255):
            candidate = f"{VPN_SUBNET}.{i}"
            if candidate not in used:
                vpn_ip = candidate
                break
        if vpn_ip is None:
            logger.error("No free VPN IPs")
            return None

        peer_block = (
            f"\n[Peer]\n"
            f"# device_id={device_id}\n"
            f"PublicKey  = {phone_pubkey}\n"
            f"AllowedIPs = {vpn_ip}/32\n"
        )
        try:
            with open(WG_CONF, "a") as f:
                f.write(peer_block)
            subprocess.run(
                ["sudo", "wg", "set", WG_IFACE,
                 "peer", phone_pubkey, "allowed-ips", f"{vpn_ip}/32"],
                check=True, timeout=10,
            )
        except Exception as exc:
            logger.warning("Could not add WireGuard peer: %s", exc)
            return None

        self._peers[device_id] = {"pubkey": phone_pubkey, "vpn_ip": vpn_ip}
        self._save_peers()
        logger.info("Added WireGuard peer %s → %s", device_id, vpn_ip)
        return {"vpn_ip": vpn_ip, "server_vpn_ip": SERVER_VPN_IP}

    def remove_peer(self, device_id: str) -> None:
        peer = self._peers.pop(device_id, None)
        if peer is None:
            return
        try:
            subprocess.run(
                ["sudo", "wg", "set", WG_IFACE, "peer", peer["pubkey"], "remove"],
                check=True, timeout=10,
            )
            self._rewrite_conf_without(peer["pubkey"])
        except Exception as exc:
            logger.warning("Could not remove WireGuard peer: %s", exc)
        self._save_peers()

    def _load_peers(self) -> dict:
        try:
            return json.loads(PEERS_DB.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _save_peers(self) -> None:
        PEERS_DB.write_text(json.dumps(self._peers, indent=2))

    def _rewrite_conf_without(self, pubkey: str) -> None:
        try:
            text    = Path(WG_CONF).read_text()
            pattern = rf"\n\[Peer\][^\[]*?PublicKey\s*=\s*{re.escape(pubkey)}[^\[]*"
            cleaned = re.sub(pattern, "", text, flags=re.DOTALL)
            Path(WG_CONF).write_text(cleaned)
        except Exception as exc:
            logger.warning("Could not rewrite wg conf: %s", exc)


# ═══════════════════════════════════════════════════════════════════════════════
# Plugin entry point
# ═══════════════════════════════════════════════════════════════════════════════

def load_component(config: Any) -> "MoongatePlugin":
    return MoongatePlugin(config)


class MoongatePlugin:
    def __init__(self, config: Any) -> None:
        self.server = config.get_server()
        self.auth   = AuthManager()
        self.wg     = WireGuardManager()

        self._wg_endpoint_override: Optional[str] = config.get(
            "wireguard_endpoint", None
        )
        # Most-recent QR URL (updated each time MOONGATE_PAIR is run)
        self._last_qr_url:      Optional[str] = None
        self._last_qr_token_id: Optional[str] = None

        # Chamber sensor — discovered once from /printer/objects/list so the
        # status endpoint can include it regardless of capitalisation:
        # [temperature_sensor chamber], [temperature_sensor CHAMBER], etc.
        self._chamber_key:         Optional[str] = None
        self._chamber_key_checked: bool          = False

        # Register HTTP endpoints using Moonraker's correct API.
        # Moonraker requires paths to start with /server, /printer, /machine, etc.
        self.server.register_endpoint(
            "/server/moongate/pair",   ["POST"], self._handle_pair
        )
        self.server.register_endpoint(
            "/server/moongate/auth",   ["POST"], self._handle_auth
        )
        self.server.register_endpoint(
            "/server/moongate/qr",     ["GET"],  self._handle_qr
        )
        self.server.register_endpoint(
            "/server/moongate/status",  ["GET"],  self._handle_status
        )
        self.server.register_endpoint(
            "/server/moongate/control", ["POST"], self._handle_control
        )
        self.server.register_endpoint(
            "/server/moongate/tokens",  ["GET"],  self._handle_list_tokens
        )
        self.server.register_endpoint(
            "/server/moongate/revoke", ["POST"], self._handle_revoke
        )
        self.server.register_endpoint(
            "/server/moongate/pair-page", ["GET"], self._handle_pair_page
        )

        # Write the static HTML pairing page to the web root so it can be
        # opened in a browser (locally or via tunnel) and shows a scannable QR.
        pair_page_path = _write_pair_page()
        if pair_page_path:
            logger.info("Moongate pair page written to %s", pair_page_path)
        else:
            logger.warning(
                "Moongate could not write pair page — no writable web-root found"
            )

        # Called by the MOONGATE_PAIR G-code macro via Klipper → Moonraker RPC
        self.server.register_remote_method(
            "moongate_generate_pair_code",
            self._klipper_generate_pair_code,
        )
        # Operator-only macros for token management — surfaced as
        # MOONGATE_LIST_TOKENS / MOONGATE_REVOKE_ALL in the Klipper console
        # by the matching `[gcode_macro …]` blocks in moongate.cfg
        self.server.register_remote_method(
            "moongate_list_tokens",
            self._klipper_list_tokens,
        )
        self.server.register_remote_method(
            "moongate_revoke_all_tokens",
            self._klipper_revoke_all_tokens,
        )

        logger.info(
            "Moongate plugin loaded (WireGuard: %s)",
            "ready" if self.wg.server_public_key() else "not configured",
        )

    # ── Klipper remote method ─────────────────────────────────────────────────

    async def _klipper_generate_pair_code(self) -> None:
        """Called when the user runs MOONGATE_PAIR in the Klipper console."""
        import asyncio

        display_code, _qr = self.auth.generate_pair_code()

        # Pre-issue a JWT for QR-based pairing.
        # The QR embeds the token directly so no phone→Pi network request is
        # needed during pairing — works even with WiFi AP isolation.
        #
        # `provisional=True` means the device-token record has a short initial
        # TTL (10 min by default) even though the JWT itself is signed for
        # the full 30 days.  If the QR is scanned and the app makes its first
        # status call within that window, [AuthManager.validate_token]
        # promotes the record to the full TTL.  If the QR URL was just
        # *shared* but never paired with, the record expires inside 10 min
        # and the token becomes invalid even though the JWT signature would
        # still verify — closing the leaked-URL exposure window.
        local_ip        = _get_local_ip()
        tunnel_url      = _get_tunnel_url()   # None if cloudflared not running
        direct_jwt, tid = self.auth.issue_direct_token(
            device_name="Paired via QR", provisional=True,
        )

        # Build the QR URL — always includes local, adds remote if tunnel is up.
        # The configured HTTP port (default 80) ends up in both the embedded
        # `local=` field (which the app stores verbatim) and the pair-page
        # URL we print to the Klipper console.
        port             = self.auth.http_port
        port_suffix      = "" if port == 80 else f":{port}"
        qr_params = f"local={local_ip}:{port}&token={direct_jwt}"
        if tunnel_url:
            qr_params += f"&remote={tunnel_url}"
        self._last_qr_url      = f"moongate://pair?{qr_params}"
        self._last_qr_token_id = tid

        local_pair_page  = f"http://{local_ip}{port_suffix}/moongate-pair.html"
        subdomain        = _get_tunnel_subdomain(tunnel_url)
        tunnel_pair_page = (
            f"{tunnel_url}/moongate-pair.html" if tunnel_url else None
        )

        logger.info("MOONGATE PAIR CODE GENERATED: %s", display_code)
        logger.info("MOONGATE LOCAL PAIR PAGE: %s", local_pair_page)
        if tunnel_url:
            logger.info("MOONGATE TUNNEL PAIR PAGE: %s", tunnel_pair_page)
            logger.info("MOONGATE TUNNEL SUBDOMAIN: %s", subdomain)
        else:
            logger.info("MOONGATE TUNNEL: not running (remote access unavailable)")

        # Let the RPC handshake complete before pushing G-code back
        await asyncio.sleep(0.3)

        # Build the console message — keep it readable in Mainsail's narrow
        # console panel; each M118 line appears on its own row.
        lines = [
            "M118 ==========================================",
            f"M118 MOONGATE CODE: {display_code}",
            "M118 ==========================================",
            "M118 ⚠ DO NOT SHARE the URL/code below.",
            "M118 Anyone with it can control this printer",
            "M118 via Mainsail without needing a token.",
            "M118 ==========================================",
        ]

        if tunnel_url and subdomain:
            # Remote user: give them the tunnel pair page URL + the subdomain
            # shortcut for typing into the app tunnel URL field.
            lines += [
                "M118 Scan QR: open this link on YOUR phone:",
                f"M118   {tunnel_pair_page}",
                "M118 -- or enter in the app tunnel field --",
                f"M118   Subdomain: {subdomain}",
                "M118   (app fills the rest automatically)",
            ]
        else:
            # Local-only: give the LAN pair page URL
            lines += [
                "M118 Scan QR: open on YOUR PC, scan with app:",
                f"M118   {local_pair_page}",
                "M118 Remote access not set up (run install.sh).",
            ]

        lines += [
            "M118 ==========================================",
            "M118 Code expires in 10 minutes.",
            "M118 If shared by accident: MOONGATE_REVOKE_ALL",
        ]
        script = "\n".join(lines)

        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
            logger.info("Pair code sent to Klipper console.")
        except Exception as exc:
            logger.error("run_gcode failed (%s) — code is: %s", exc, display_code)

        # Also push via WebSocket so Mainsail shows it
        ws_msg = f"// MOONGATE CODE: {display_code}"
        if tunnel_pair_page:
            ws_msg += f" — tap to pair: {tunnel_pair_page}"
        elif local_pair_page:
            ws_msg += f" — QR page: {local_pair_page}"
        try:
            self.server.send_event("server:gcode_response", ws_msg)
        except Exception:
            pass

    async def _klipper_list_tokens(self) -> None:
        """Called from the Klipper console via MOONGATE_LIST_TOKENS.  Dumps
        each issued token (revoked + active) to the Mainsail console as
        M118 lines so the operator can audit who has access without needing
        to SSH in and read tokens.json."""
        import asyncio
        tokens = self.auth.list_tokens()
        await asyncio.sleep(0.3)

        if not tokens:
            lines = [
                "M118 ============================================",
                "M118 No Moongate tokens issued yet.",
                "M118 ============================================",
            ]
        else:
            # Sort newest first so the most-likely-suspect (e.g. one just
            # leaked) shows at the top
            tokens.sort(key=lambda t: t.get("issued_at", 0), reverse=True)
            lines = [
                "M118 ============================================",
                f"M118 Moongate tokens ({len(tokens)} total):",
                "M118 --------------------------------------------",
            ]
            for t in tokens:
                issued = time.strftime(
                    "%Y-%m-%d %H:%M",
                    time.localtime(t.get("issued_at", 0)),
                )
                state = []
                if t.get("revoked"):       state.append("REVOKED")
                elif not t.get("valid"):   state.append("EXPIRED")
                else:                      state.append("active")
                if t.get("provisional"):   state.append("provisional")
                lines.append(
                    f"M118 [{','.join(state)}] {t.get('device_name', '?')} "
                    f"({issued}) id={t.get('token_id', '?')[:8]}…"
                )
            lines.append("M118 ============================================")
            lines.append("M118 To revoke all: MOONGATE_REVOKE_ALL")
        script = "\n".join(lines)
        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
        except Exception as exc:
            logger.error("MOONGATE_LIST_TOKENS run_gcode failed: %s", exc)

    async def _klipper_revoke_all_tokens(self) -> None:
        """Called from the Klipper console via MOONGATE_REVOKE_ALL.  Revokes
        every active token in one shot — every paired Moongate device will
        need to re-pair.  Intended for incident response: pair URL leaked,
        QR shown on stream by accident, lost phone, etc."""
        import asyncio
        count = self.auth.revoke_all_tokens()
        await asyncio.sleep(0.3)

        lines = [
            "M118 ============================================",
            f"M118 Moongate: {count} active token(s) revoked.",
            "M118 Every paired device must re-pair to access.",
            "M118 Run MOONGATE_PAIR for each device to re-add.",
            "M118 ============================================",
        ]
        script = "\n".join(lines)
        try:
            klippy_apis: Any = self.server.lookup_component("klippy_apis")
            await klippy_apis.run_gcode(script)
        except Exception as exc:
            logger.error("MOONGATE_REVOKE_ALL run_gcode failed: %s", exc)

    # ── Route handlers ────────────────────────────────────────────────────────
    # Moonraker WebRequest: use webrequest.get_args() for body/query params.
    # Raise self.server.error("msg", status_code) for HTTP errors.

    async def _handle_pair(self, webrequest: Any) -> dict:
        """
        Generate a pairing session and return both formats:

          • code / GATE code  — for manual entry; requires phone→Pi network to
                                exchange for a token (/server/moongate/auth)
          • qr_payload        — moongate://pair?local=…&remote=…&token=JWT
                                Phone stores the pre-issued token directly;
                                no network request needed at scan time, so QR
                                pairing works even over WiFi AP-isolated networks
                                or from a completely different network via tunnel.
        """
        import urllib.parse
        display_code, _ = self.auth.generate_pair_code()

        # Pre-issue a token for the QR path
        direct_jwt, tid  = self.auth.issue_direct_token(device_name="Paired via QR")
        local_ip         = _get_local_ip()
        tunnel_url       = _get_tunnel_url()
        port             = self.auth.http_port

        params: dict = {"local": f"{local_ip}:{port}", "token": direct_jwt}
        if tunnel_url:
            params["remote"] = tunnel_url
        qr_payload = "moongate://pair?" + urllib.parse.urlencode(params)

        # Cache for the /server/moongate/qr endpoint (used by the QR web page)
        self._last_qr_url      = qr_payload
        self._last_qr_token_id = tid

        logger.info("Pair code requested via HTTP: %s", display_code)
        return {
            "code":               display_code,
            "qr_payload":         qr_payload,
            "local_url":          f"http://{local_ip}:{port}",
            "tunnel_url":         tunnel_url,
            "expires_in_seconds": 600,
        }

    async def _handle_qr(self, webrequest: Any) -> dict:
        """
        Return the pre-issued QR URL for the most-recent MOONGATE_PAIR run.
        Format: moongate://pair?local=IP:80&remote=https://x.trycloudflare.com&token=JWT
        The app stores the token directly — no phone→Pi network request needed.
        Called by moongate-pair.html served on the printer's web UI.
        """
        if self._last_qr_url is None:
            raise self.server.error(
                "No pairing session active. Run MOONGATE_PAIR first.", 404
            )
        tunnel_url = _get_tunnel_url()
        return {
            "qr_url":     self._last_qr_url,
            "tunnel_url": tunnel_url,         # None if cloudflared not running
        }

    async def _handle_auth(self, webrequest: Any) -> dict:
        args         = webrequest.get_args()
        raw_code     = args.get("code", "")
        device_name  = args.get("device_name", "Unknown device")
        ttl_days     = args.get("ttl_days")
        phone_pubkey = args.get("wg_pubkey")

        if not raw_code:
            raise self.server.error("code is required", 400)

        result = self.auth.exchange_code(
            raw_code=raw_code,
            device_name=str(device_name),
            requested_ttl_days=int(ttl_days) if ttl_days is not None else None,
        )
        if result is None:
            raise self.server.error("invalid or expired code", 401)

        token, token_id = result
        response: dict  = {"token": token}

        if phone_pubkey:
            server_pubkey = self.wg.server_public_key()
            endpoint      = self.wg.endpoint(self._wg_endpoint_override)
            if server_pubkey and endpoint:
                peer_info = self.wg.add_peer(
                    device_id=token_id, phone_pubkey=str(phone_pubkey)
                )
                if peer_info:
                    wg_config = (
                        "[Interface]\n"
                        f"Address    = {peer_info['vpn_ip']}/32\n"
                        "DNS        = 1.1.1.1\n\n"
                        "[Peer]\n"
                        f"PublicKey           = {server_pubkey}\n"
                        f"Endpoint            = {endpoint}\n"
                        f"AllowedIPs          = {peer_info['server_vpn_ip']}/32\n"
                        "PersistentKeepalive = 25\n"
                    )
                    response["wg_config"]    = wg_config
                    response["wg_server_ip"] = peer_info["server_vpn_ip"]
                    response["wg_phone_ip"]  = peer_info["vpn_ip"]
                    logger.info(
                        "WireGuard peer created for '%s' → %s",
                        device_name, peer_info["vpn_ip"],
                    )
            else:
                logger.info("WireGuard not configured — skipping wg_config")

        return response

    @staticmethod
    async def _get_webcam_info(client: Any) -> dict:
        """
        Ask Moonraker for its webcam configuration and return the snapshot path
        plus the display-transform settings (rotation, flip_horizontal,
        flip_vertical) that Mainsail/Fluidd apply client-side.

        The app must apply the same transforms when rendering the snapshot so
        the tile image matches the orientation shown in the full web UI.

        Falls back to safe defaults if the webcam API is unavailable.
        """
        import re as _re
        from tornado.httpclient import HTTPRequest

        _default_path = "/webcam/?action=snapshot"
        # 15 fps is the Crowsnest / mjpg-streamer default for a stock install,
        # so it's the safest fallback when no target_fps is configured.
        _default_fps = 15
        _defaults = {
            "snapshot_path":   _default_path,
            "flip_horizontal": False,
            "flip_vertical":   False,
            "rotation":        0,
            "target_fps":      _default_fps,
        }
        try:
            req = HTTPRequest(
                "http://127.0.0.1:7125/server/webcams/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return _defaults
            data    = __import__("json").loads(resp.body)
            webcams = data.get("result", {}).get("webcams", [])
            if not webcams:
                return _defaults
            cam  = webcams[0]
            snap = (cam.get("snapshot_url") or "").strip()
            if not snap:
                return _defaults
            # Strip localhost prefix so only the path survives.
            snap = _re.sub(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?', '', snap)
            # target_fps is the Crowsnest/Mainsail "Webcam → Target FPS" field.
            # Clamp to [1, 60] — anything outside is suspect (Mainsail won't
            # serve faster than the camera can produce frames anyway, but
            # we'd rather not let a typo turn the snapshot poll into a
            # millisecond-tight loop).
            raw_fps = cam.get("target_fps", _default_fps)
            try:
                tgt_fps = int(raw_fps)
                if tgt_fps < 1 or tgt_fps > 60:
                    tgt_fps = _default_fps
            except (TypeError, ValueError):
                tgt_fps = _default_fps
            return {
                "snapshot_path":   snap or _default_path,
                # Mainsail stores these as booleans; default False / 0 if absent.
                "flip_horizontal": bool(cam.get("flip_horizontal", False)),
                "flip_vertical":   bool(cam.get("flip_vertical",   False)),
                "rotation":        int(cam.get("rotation", 0)),
                "target_fps":      tgt_fps,
            }
        except Exception:
            return _defaults

    async def _discover_chamber_sensor(self, client: Any) -> Optional[str]:
        """
        Call /printer/objects/list and return the first temperature_sensor or
        heater_generic key whose name contains 'chamber' (case-insensitive).

        Handles any capitalisation the user chose in printer.cfg:
          [temperature_sensor chamber]       → "temperature_sensor chamber"
          [temperature_sensor CHAMBER]       → "temperature_sensor CHAMBER"
          [temperature_sensor Chamber_Temp]  → "temperature_sensor Chamber_Temp"
          [heater_generic CHAMBER]           → "heater_generic CHAMBER"
        """
        from tornado.httpclient import HTTPRequest
        try:
            req  = HTTPRequest(
                "http://127.0.0.1:7125/printer/objects/list",
                method="GET", request_timeout=2.0,
            )
            resp = await client.fetch(req, raise_error=False)
            if resp.code != 200:
                return None
            import json as _j
            objects = _j.loads(resp.body).get("result", {}).get("objects", [])
            for obj in objects:
                if ("temperature_sensor" in obj or "heater_generic" in obj
                        or "temperature_fan" in obj) \
                        and "chamber" in obj.lower():
                    logger.info("Moongate: chamber sensor detected: '%s'", obj)
                    return obj
        except Exception:
            pass
        return None

    async def _handle_status(self, webrequest: Any) -> dict:
        """
        Authenticated proxy for Moonraker printer status.
        Validates the Moongate JWT, then fetches live printer data from
        Moonraker on localhost (trusted connection — no second auth needed).
        Uses tornado's built-in AsyncHTTPClient (no extra packages needed).
        """
        self._authenticate(webrequest)
        import json as _json
        import urllib.parse
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        client = AsyncHTTPClient()

        # Discover which temperature_sensor/heater_generic key is the chamber
        # sensor (once per plugin lifetime — handles any user capitalisation).
        if not self._chamber_key_checked:
            self._chamber_key         = await self._discover_chamber_sensor(client)
            self._chamber_key_checked = True

        # Build query: always include core objects; add chamber sensor if found.
        query = "print_stats&heater_bed&extruder"
        if self._chamber_key:
            query += "&" + urllib.parse.quote(self._chamber_key, safe="")

        req = HTTPRequest(
            f"http://127.0.0.1:7125/printer/objects/query?{query}",
            method="GET",
            request_timeout=5.0,
        )
        try:
            # raise_error=False → HTTPError not thrown on non-200; we check manually
            resp = await client.fetch(req, raise_error=False)
        except Exception as e:
            raise self.server.error(
                f"Failed to reach Moonraker internally: {e}", 500
            )
        if resp.code != 200:
            raise self.server.error(
                f"Moonraker query returned HTTP {resp.code}", 502
            )
        data   = _json.loads(resp.body)
        result = data.get("result", data)

        # Inject the Pi's current tunnel URL so the app can detect staleness
        # and update its stored remoteHost without the user re-scanning the QR.
        result["tunnel_url"] = _get_tunnel_url()

        # Inject webcam snapshot path AND display-transform settings so the app
        # can apply the same rotation/flip that Mainsail shows in the browser.
        webcam = await self._get_webcam_info(client)
        result["webcam_snapshot_path"]   = webcam["snapshot_path"]
        result["webcam_flip_horizontal"] = webcam["flip_horizontal"]
        result["webcam_flip_vertical"]   = webcam["flip_vertical"]
        result["webcam_rotation"]        = webcam["rotation"]
        # Crowsnest / Mainsail "Target FPS" — the app uses this to time its
        # snapshot poll, so a 15 fps stream really animates at 15 fps on the
        # tile rather than the previous hard-coded value.
        result["webcam_target_fps"]      = webcam["target_fps"]

        return result

    async def _handle_control(self, webrequest: Any) -> dict:
        """
        Authenticated proxy for Klipper print control actions.
        POST /server/moongate/control?mg_token=<jwt>&action=<action>

        Supported actions:
          pause          — pause the current print
          resume         — resume a paused print
          cancel         — cancel the current print (requires double-press in app)
          emergency_stop — immediately halt all motion (Klipper shutdown state)
        """
        self._authenticate(webrequest)
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        args   = webrequest.get_args()
        action = str(args.get("action", "")).strip()

        action_map = {
            "pause":             "/printer/print/pause",
            "resume":            "/printer/print/resume",
            "cancel":            "/printer/print/cancel",
            "emergency_stop":    "/printer/emergency_stop",
            "firmware_restart":  "/printer/firmware_restart",
        }
        if action not in action_map:
            raise self.server.error(
                f"Unknown action '{action}'. Valid: {list(action_map)}", 400
            )

        path   = action_map[action]
        client = AsyncHTTPClient()
        req    = HTTPRequest(
            f"http://127.0.0.1:7125{path}",
            method="POST",
            body="{}",
            headers={"Content-Type": "application/json"},
            request_timeout=10.0,
        )
        try:
            resp = await client.fetch(req, raise_error=False)
        except Exception as e:
            raise self.server.error(
                f"Failed to reach Moonraker internally: {e}", 500
            )
        if resp.code not in (200, 204):
            raise self.server.error(
                f"Moonraker returned HTTP {resp.code} for action '{action}'", 502
            )
        return {"action": action, "ok": True}

    async def _handle_pair_page(self, webrequest: Any) -> dict:
        """
        Returns metadata needed to build the pairing UI.
        The actual HTML page (moongate-pair.html) is written to the nginx
        web-root at startup — this endpoint is only a JSON fallback used by
        that page to fetch the current QR URL.
        """
        tunnel_url = _get_tunnel_url()
        subdomain  = _get_tunnel_subdomain(tunnel_url)
        return {
            "qr_url":    self._last_qr_url,
            "tunnel_url": tunnel_url,
            "subdomain":  subdomain,
            "local_ip":   _get_local_ip(),
            "ready":      self._last_qr_url is not None,
        }

    async def _handle_list_tokens(self, webrequest: Any) -> dict:
        self._authenticate(webrequest)
        return {"tokens": self.auth.list_tokens()}

    async def _handle_revoke(self, webrequest: Any) -> dict:
        token_id  = self._authenticate(webrequest)
        args      = webrequest.get_args()
        target_id = args.get("token_id", token_id)
        self.wg.remove_peer(str(target_id))
        success = self.auth.revoke_token(str(target_id))
        return {"revoked": success}

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _authenticate(self, webrequest: Any) -> str:
        """
        Validate the Moongate JWT passed as ?mg_token=<jwt>.
        Note: Moonraker strips 'token' and 'access_token' from get_args()
        (they appear in EXCLUDED_ARGS in application.py), so we use the
        custom parameter name 'mg_token' which Moonraker leaves untouched.
        Raises 401 if missing or invalid. Returns token_id on success.
        """
        args  = webrequest.get_args()
        token = args.get("mg_token", "")
        if not token:
            raise self.server.error("Authorization token required", 401)
        token_id = self.auth.validate_token(str(token))
        if token_id is None:
            raise self.server.error("Invalid or expired token", 401)
        return token_id
