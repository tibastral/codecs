/*
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
