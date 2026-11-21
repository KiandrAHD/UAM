//! Scoped COM apartment initialization.
//!
//! Every public backend call runs inside a multi-threaded apartment. The guard
//! owns a matching `CoUninitialize` only when this thread actually performed the
//! initialization, which keeps the call balanced when the operating system or a
//! host already initialized COM.

use windows::Win32::Foundation::RPC_E_CHANGED_MODE;
use windows::Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_MULTITHREADED};

use crate::error::{AudioError, AudioErrorCode};

/// An initialized COM apartment for the current thread.
///
/// Dropping the guard balances a successful `CoInitializeEx`.
pub struct ComApartment {
    owns: bool,
}

impl ComApartment {
    /// Initialize COM in multi-threaded mode for the current thread.
    ///
    /// # Errors
    ///
    /// Returns [`AudioErrorCode::ComInitialization`] when `CoInitializeEx`
    /// fails with an error other than a pre-existing different apartment mode.
    pub fn initialize() -> Result<Self, AudioError> {
        // SAFETY: no reserved pointer is passed; the result is checked and the
        // matching CoUninitialize runs in Drop when we own the initialization.
        let result = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        if result.is_ok() {
            Ok(Self { owns: true })
        } else if result == RPC_E_CHANGED_MODE {
            // The thread already lives in a single-threaded apartment. Windows
            // still lets us create MTA objects, so we borrow the existing
            // apartment and must not uninitialize it.
            Ok(Self { owns: false })
        } else {
            Err(AudioError::new(
                AudioErrorCode::ComInitialization,
                format!("CoInitializeEx failed with {result:?}"),
            ))
        }
    }
}

impl Drop for ComApartment {
    fn drop(&mut self) {
        if self.owns {
            // SAFETY: balanced with the successful CoInitializeEx above.
            unsafe { CoUninitialize() };
        }
    }
}
