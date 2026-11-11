#include "core/config/engine.h"
#include "core/object/class_db.h"

extern "C" {
int32_t hamster_ar_supported();
int32_t hamster_ar_open(int32_t mask);
int32_t hamster_ar_take_event();
void hamster_ar_close();
}

class HamsterAR : public Object {
	GDCLASS(HamsterAR, Object);

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("is_supported"), &HamsterAR::is_supported);
		ClassDB::bind_method(D_METHOD("open", "gray", "white"), &HamsterAR::open);
		ClassDB::bind_method(D_METHOD("take_event"), &HamsterAR::take_event);
		ClassDB::bind_method(D_METHOD("close"), &HamsterAR::close);
	}

public:
	bool is_supported() const { return hamster_ar_supported() != 0; }
	bool open(bool gray, bool white) { return hamster_ar_open((gray ? 1 : 0) | (white ? 2 : 0)) != 0; }
	int take_event() const { return hamster_ar_take_event(); }
	void close() { hamster_ar_close(); }
};

static HamsterAR *hamster_ar = nullptr;

extern "C" void hamster_ar_init() {
	GDREGISTER_CLASS(HamsterAR);
	hamster_ar = memnew(HamsterAR);
	Engine::get_singleton()->add_singleton(Engine::Singleton("HamsterAR", hamster_ar));
}

extern "C" void hamster_ar_deinit() {
	hamster_ar_close();
	Engine::get_singleton()->remove_singleton("HamsterAR");
	memdelete(hamster_ar);
	hamster_ar = nullptr;
}
