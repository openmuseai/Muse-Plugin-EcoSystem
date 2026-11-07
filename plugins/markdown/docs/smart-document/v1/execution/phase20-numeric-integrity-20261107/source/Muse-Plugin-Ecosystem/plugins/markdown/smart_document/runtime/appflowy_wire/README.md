# Original AppFlowy full-sync wire adapter

Shared Rust package for content bindings using the pinned original Yrs/AppFlowy Cloud protocol. It accepts an object ID, original collab type, opaque state vector and document state. Database roots use original type 1 and rows type 4; the document domain uses type 0. Each domain still validates addresses, state and commands.

This extracts the existing document adapter without changing protocol fields or compression semantics. The Cloud response is bounded Zstandard; the request uses the original NONE compression variant. Transport success is not a durable storage acknowledgement. Other merge engines require their own explicit protocol/binding.
