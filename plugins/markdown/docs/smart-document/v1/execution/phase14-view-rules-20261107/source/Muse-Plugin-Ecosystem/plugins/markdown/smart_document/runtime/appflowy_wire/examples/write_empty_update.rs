//! Golden test response produced by the same Zstandard encoder as Cloud.
fn main(){
 let target=std::env::args().nth(1).expect("output path required");
 let encoded=zstd::encode_all([0u8,0u8].as_slice(),0).unwrap();
 std::fs::write(target,encoded).unwrap();
}
