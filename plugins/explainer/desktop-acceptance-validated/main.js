export async function run(api) {
  const documents = await api.readAll();
  return {
    title: 'Workspace document explainer',
    documents: documents.map(({ capability, snapshot }) => ({
      capability,
      name: snapshot.name,
      pages: snapshot.pageCount,
      textStatus: snapshot.status,
      outline: snapshot.pages.slice(0, 3).map(page => ({
        page: page.index + 1,
        text: page.text.slice(0, 360),
      })),
    })),
    comparison: '已并行读取两份资料的真实文字层。可在此添加比较、讲解或其他业务逻辑。',
  };
}
