export async function run(api) {
  await api.mountNarration();
  document.querySelector("strong").textContent = "PPTX / PDF ";
}
