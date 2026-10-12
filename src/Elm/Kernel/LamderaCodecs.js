/*
import Result exposing (Ok)
import Maybe exposing (Just, Nothing)
import Bytes.Decode as Decode exposing (Decoder)
import Elm.Kernel.Bytes exposing (read_string)
import Elm.Kernel.List exposing (fromArray)
import Elm.Kernel.Utils exposing (Tuple2)
*/

var wireRefs = (function () {
  var refs = new Map();
  var counter = 0; // uInt32 max
  var f = {}
  f.add = function(obj) {
    counter++;
    refs.set(counter, obj);
    return counter;
  }
  f.getFinal = function(k) {
    let v = refs.get(k);
    refs.delete(k);
    return v;
  }
  f.clear = function() {
    refs = new Map();
  };
  f.all = function() {
    return [refs.keys(), refs];
  }
  return f;
})();

var _LamderaCodecs_encodeWithRef = function(a) {
  return wireRefs.add(a);
}

var _LamderaCodecs_decodeWithRef = function(ref) {
  return wireRefs.getFinal(ref);
}

var _LamderaCodecs_encodeBytes = function(s) { return _Lamdera_Json_wrap(s); }

function _Lamdera_Json_wrap__DEBUG(value) { return { $: __0_JSON, a: value }; }
function _Lamdera_Json_wrap__PROD(value) { return value; }

function _LamderaCodecs_Json_decodePrim(decoder) {
  return { $: __1_PRIM, __decoder: decoder };
}

var _LamderaCodecs_decodeBytes = _Json_decodePrim(function(value) {
  return (typeof value === 'object' && value instanceof DataView)
    ? __Result_Ok(value)
    : _Json_expecting('a DataView', value) ;
    // : console.log('error: expecting DataView, got', value) ;
});

var _LamderaCodecs_debug = function(s) {
  console.log(s);
  return _Utils_Tuple0;
}

// The function inside an elm/bytes `Decoder`. With --optimize, single-constructor
// types are unboxed and the decoder IS the function; without it, the decoder is
// `{ $: 'Decoder', a: function }`.
function _LamderaCodecs_unwrapDecoder__DEBUG(decoder) { return decoder.a; }
function _LamderaCodecs_unwrapDecoder__PROD(decoder) { return decoder; }

// Duplicate of _Bytes_decode that expects all bytes to be consumed,
// otherwise it fails to decode.
var _LamderaCodecs_bytesDecodeStrict = F2(function(decoder, bytes)
{
  try {
    var res = A2(_LamderaCodecs_unwrapDecoder(decoder), bytes, 0);
    const w = bytes.byteLength;
    if (w !== res.a) {
      // For now just log issues, in future we'll actually fail on this case
      console.log(`❌ bytesDecodeStrict did not consume all bytes: length:${w}, consumed:${res.a}`, res.b, new Uint8Array(bytes.buffer));
    }
    return __Maybe_Just(res.b);
  } catch(e) {
    console.log('❌ bytesDecodeStrict unexpected error:', e);
    return __Maybe_Nothing;
  }
});


// DIRECT DECODERS
//
// The Wire3 decoders below read their bytes directly and allocate a single
// (offset, value) tuple, the elm/bytes decoder protocol. The Elm versions they
// replace stack `andThen`, `map` and `succeed`, each of which allocates closures
// and intermediate decoders: decoding a single one-byte Int used to allocate
// about six objects. On a 16 MB snapshot from a production app, decoding went
// from ~780 ms to ~60 ms (Node 26, Apple M1), most of the old cost being garbage
// collection.
//
// They return exactly what the Elm versions returned, for any input bytes,
// including malformed ones: same values, same offsets, and a failure (a throw,
// which `Bytes.Decode.decode` turns into `Nothing`) wherever the Elm version
// failed. tests/Equivalence.elm checks this against the previous Elm
// implementations.
//
// `decodeInt64`, `decodeString` and `decodeBool` are functions of `()` rather
// than values: elm/bytes' `Decoder` constructor is not defined yet when this
// kernel module is evaluated.

// The offset reached by the last _LamderaCodecs_readInt64, kept here to avoid
// allocating a tuple for it.
var _LamderaCodecs_offset = 0;

// Reads a Wire3 varint at `offset` (see decodeInt64 in Lamdera/Wire3.elm) and
// leaves the next offset in _LamderaCodecs_offset.
function _LamderaCodecs_readInt64(bytes, offset)
{
	var n0 = bytes.getUint8(offset);
	var u;
	if (n0 <= 215) { u = n0; offset += 1; }
	else if (n0 < 252) { u = (n0 - 216) * 256 + bytes.getUint8(offset + 1) + 216; offset += 2; }
	else if (n0 === 252) { u = bytes.getUint8(offset + 1) * 256 + bytes.getUint8(offset + 2); offset += 3; }
	else if (n0 === 253) { u = (bytes.getUint8(offset + 1) * 256 + bytes.getUint8(offset + 2)) * 256 + bytes.getUint8(offset + 3); offset += 4; }
	else if (n0 === 254) { u = ((bytes.getUint8(offset + 1) * 256 + bytes.getUint8(offset + 2)) * 256 + bytes.getUint8(offset + 3)) * 256 + bytes.getUint8(offset + 4); offset += 5; }
	else
	{
		// 255: a little-endian Float64, NOT mapped through unsignedToSigned.
		var f = bytes.getFloat64(offset + 1, true);
		if (f !== f || f === Infinity || f === -Infinity) { throw 0; }
		_LamderaCodecs_offset = offset + 9;
		return Math.floor(f);
	}
	_LamderaCodecs_offset = offset;
	// unsignedToSigned
	return (u % 2 === 1) ? -((u + 1) / 2) : u / 2;
}

var _LamderaCodecs_decodeInt64 = function(_unit)
{
	return __Decode_Decoder(F2(function(bytes, offset)
	{
		var value = _LamderaCodecs_readInt64(bytes, offset);
		return __Utils_Tuple2(_LamderaCodecs_offset, value);
	}));
};

var _LamderaCodecs_utf8 = typeof TextDecoder === 'undefined'
	? null
	: new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

var _LamderaCodecs_decodeString = function(_unit)
{
	return __Decode_Decoder(F2(function(bytes, offset)
	{
		var len = _LamderaCodecs_readInt64(bytes, offset);
		var start = _LamderaCodecs_offset;
		// Like elm/bytes' string decoder: a length <= 0 reads nothing and does not move.
		if (len <= 0) { return __Utils_Tuple2(start, ''); }
		var end = start + len;
		if (end > bytes.byteLength) { throw 0; }
		// Short ASCII strings: read in place, without a view or a native call.
		if (len <= 32)
		{
			var s = '';
			for (var i = start; i < end; i++)
			{
				var b = bytes.getUint8(i);
				if (b >= 128) { s = null; break; }
				s += String.fromCharCode(b);
			}
			if (s !== null) { return __Utils_Tuple2(end, s); }
		}
		if (_LamderaCodecs_utf8 !== null)
		{
			try
			{
				return __Utils_Tuple2(end, _LamderaCodecs_utf8.decode(new Uint8Array(bytes.buffer, bytes.byteOffset + start, len)));
			}
			catch (e)
			{
				// Not valid UTF-8 (a lone surrogate, which elm/bytes' encoder writes
				// as is, or a sequence cut by the end of the string): elm/bytes'
				// own decoder handles it exactly as before.
			}
		}
		return A3(__Bytes_read_string, len, bytes, start);
	}));
};

var _LamderaCodecs_decodeBool = function(_unit)
{
	return __Decode_Decoder(F2(function(bytes, offset)
	{
		var b = bytes.getUint8(offset);
		if (b === 0) { return __Utils_Tuple2(offset + 1, false); }
		if (b === 1) { return __Utils_Tuple2(offset + 1, true); }
		throw 0;
	}));
};

var _LamderaCodecs_decodeList = function(decoder)
{
	var decode = _LamderaCodecs_unwrapDecoder(decoder);
	return __Decode_Decoder(F2(function(bytes, offset)
	{
		var len = _LamderaCodecs_readInt64(bytes, offset);
		offset = _LamderaCodecs_offset;
		var items = [];
		for (var i = 0; i < len; i++)
		{
			var r = A2(decode, bytes, offset);
			offset = r.a;
			items.push(r.b);
		}
		return __Utils_Tuple2(offset, __List_fromArray(items));
	}));
};

var _LamderaCodecs_decodeMaybe = function(decoder)
{
	var decode = _LamderaCodecs_unwrapDecoder(decoder);
	return __Decode_Decoder(F2(function(bytes, offset)
	{
		var tag = bytes.getUint8(offset);
		if (tag === 0) { return __Utils_Tuple2(offset + 1, __Maybe_Nothing); }
		if (tag === 1)
		{
			var r = A2(decode, bytes, offset + 1);
			return __Utils_Tuple2(r.a, __Maybe_Just(r.b));
		}
		throw 0;
	}));
};

// andMapDecode d d2: d2 decodes a function, then d decodes its argument,
// in the same order as the Elm version.
var _LamderaCodecs_andMapDecode = F2(function(decoder, functionDecoder)
{
	var decode = _LamderaCodecs_unwrapDecoder(decoder);
	var decodeFunction = _LamderaCodecs_unwrapDecoder(functionDecoder);
	return __Decode_Decoder(F2(function(bytes, offset)
	{
		var rf = A2(decodeFunction, bytes, offset);
		var rx = A2(decode, bytes, rf.a);
		return __Utils_Tuple2(rx.a, rf.b(rx.b));
	}));
});
