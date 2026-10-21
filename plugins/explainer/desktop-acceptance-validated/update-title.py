from pathlib import Path

source = Path(__file__).with_name('main.js')
text = source.read_text()
old = "title: 'PPTX + PDF 多资料讲解助手'"
new = "title: 'Workspace document explainer'"
assert old in text, 'Expected generated template title'
source.write_text(text.replace(old, new, 1))
print('Saved main.js: Workspace document explainer')
