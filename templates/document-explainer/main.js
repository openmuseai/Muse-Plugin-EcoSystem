// Independent live resource extension. The adapter library is bundled in MCPB;
// no Host, GenOffice or PDF source imports are needed.
export async function run(api) {
  return api.mountNarration();
}
