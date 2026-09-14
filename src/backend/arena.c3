module backend::arena;

struct MemoryArena {
	char* bfr;
	usz capacity;
	usz used;
}

fn void MemoryArena.init(&self, usz init_cap = 1048576){
	self.capacity = init_cap > 65536 ? init_cap : 65536;
	self.bfr = (char*)mem::alloc_array(char, (sz)self.capacity);
	self.used = 0;
}

fn void MemoryArena.free(&self){
	if(self.bfr != null){
		mem::free(self.bfr);
		self.bfr = null;
		self.capacity = 0;
		self.used = 0;
	}
}

fn void* MemoryArena.bump_alloc(&self, usz bytes){
	usz aligned = align_bytes(bytes);
	usz bump_sz = self.used + aligned;
	if(self.bfr != null && self.capacity < bump_sz){
		usz aug_cap = self.capacity * 2; // /aug_cap mane augmented cap. I legit searched for synonyms to use lol!
		if (aug_cap < bump_sz) aug_cap = bump_sz + 65536;
		self.bfr = (char*)mem::realloc(self.bfr, (sz)aug_cap);
		self.capacity = aug_cap;
	}

	void* ptr = self.bfr + self.used;
	self.used += aligned;

	return ptr;
}

fn String MemoryArena.append_string(&self, String s){
	char* dest = (char*)self.bump_alloc(s.len + 1);
	mem::copy(dest, s.ptr, s.len);
	dest[s.len] = 0;
	return (String)dest[0 : s.len];
}

// Helper functions.
fn usz align_bytes(usz bytes){
	return (bytes + 7) & ~7;
}