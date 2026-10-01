/* Deterministic input and audio capture for the headless gameplay probes. */
#include <SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static Uint8 keys[512], buttons[21];
static Uint32 queued;
static int energy, pad_attached;
static FILE *recording;

char *SDL_GetPrefPath(const char *org, const char *app) {
    (void)org; (void)app;
    return SDL_strdup(getenv("ION_TEST_PREFS"));
}

void ion_test_key(int code, int down) { keys[code] = (Uint8)down; }
void ion_test_pad(int button, int down) {
    pad_attached = 1;
    buttons[button] = (Uint8)down;
}
const Uint8 *SDL_GetKeyboardState(int *count) { *count = 512; return keys; }
int SDL_NumJoysticks(void) { return pad_attached; }
SDL_bool SDL_IsGameController(int index) { return index == 0 && pad_attached; }
SDL_JoystickID SDL_JoystickGetDeviceInstanceID(int index) { (void)index; return 1; }
SDL_GameController *SDL_GameControllerOpen(int index) {
    (void)index; return (SDL_GameController *)(uintptr_t)1;
}
void SDL_GameControllerClose(SDL_GameController *controller) { (void)controller; }
SDL_bool SDL_GameControllerGetAttached(SDL_GameController *controller) {
    (void)controller; return pad_attached;
}
SDL_GameControllerType SDL_GameControllerGetType(SDL_GameController *controller) {
    (void)controller; return SDL_CONTROLLER_TYPE_XBOXONE;
}
Sint16 SDL_GameControllerGetAxis(SDL_GameController *controller, SDL_GameControllerAxis axis) {
    (void)controller; (void)axis; return 0;
}
Uint8 SDL_GameControllerGetButton(SDL_GameController *controller, SDL_GameControllerButton button) {
    (void)controller; return buttons[button];
}
SDL_AudioDeviceID SDL_OpenAudioDevice(const char *name, int capture,
                                     const SDL_AudioSpec *desired,
                                     SDL_AudioSpec *obtained, int changes) {
    (void)name; (void)capture; (void)changes;
    *obtained = *desired; return 1;
}
void SDL_CloseAudioDevice(SDL_AudioDeviceID device) { (void)device; }
void SDL_PauseAudioDevice(SDL_AudioDeviceID device, int paused) { (void)device; (void)paused; }
void SDL_ClearQueuedAudio(SDL_AudioDeviceID device) { (void)device; queued = 0; }
Uint32 SDL_GetQueuedAudioSize(SDL_AudioDeviceID device) { (void)device; return queued; }
int SDL_QueueAudio(SDL_AudioDeviceID device, const void *data, Uint32 length) {
    const int16_t *samples = data;
    (void)device;
    for (Uint32 i = 0; i < length / 2; ++i) energy += abs(samples[i]);
    if (recording) fwrite(data, 1, length, recording);
    queued += length; return 0;
}
void ion_test_drain(void) { queued = 0; energy = 0; }
int ion_test_energy(void) { return energy; }
void ion_test_frame(const uint32_t *pixels, int slot) {
    char path[80];
    snprintf(path, sizeof(path), "build/quality-probe/screen-%d.ppm", slot);
    FILE *file = fopen(path, "wb");
    if (!file) exit(90);
    fprintf(file, "P6\n320 180\n255\n");
    for (int i = 0; i < 320 * 180; ++i) {
        unsigned char rgb[3] = {pixels[i] >> 16, pixels[i] >> 8, pixels[i]};
        fwrite(rgb, 1, 3, file);
    }
    if (fclose(file)) exit(91);
}
void ion_test_record(int track) {
    if (recording) { fclose(recording); recording = NULL; }
    if (track >= 0) {
        char path[80];
        snprintf(path, sizeof(path), "build/quality-probe/track-%d.s16", track);
        recording = fopen(path, "wb");
        if (!recording) exit(92);
    }
}
