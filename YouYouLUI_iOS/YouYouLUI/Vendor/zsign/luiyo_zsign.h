#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// In-app IPA signing, backed by the vendored zsign engine
/// (Vendor/zsign-src, MIT — see Vendor/zsign-LICENSE.txt).
///
/// Signs `ipaPath` with the P12 at `p12Path` (unlocked with
/// `password`) and the provisioning profile at `profilePath`:
/// the profile is embedded, every Mach-O in the bundle (app,
/// frameworks, extensions, dylibs) is signed with the profile's
/// entitlements, and the result is written to `outputPath`.
/// `tempDir` must be an existing writable directory; the engine
/// unpacks and repacks the IPA there.
///
/// Returns 0 on success. On failure returns a nonzero engine exit
/// code and, when `errorBuffer` is non-NULL, fills it with the
/// tail of the engine's own log output so the UI can surface what
/// the engine actually said.
int luiyo_zsign_sign(const char* ipaPath,
                     const char* p12Path,
                     const char* password,
                     const char* profilePath,
                     const char* outputPath,
                     const char* tempDir,
                     char* errorBuffer,
                     int errorBufferSize);

#ifdef __cplusplus
}
#endif
