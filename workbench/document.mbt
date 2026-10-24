///|
/// 常驻 Studio 文档 id。工程文件 id 带 `file:` 前缀，顶层文件即使叫
/// `studio` 也不会撞上常驻文档。
pub const STUDIO_DOC_ID : String = "studio"

///|
pub fn file_document_id(rel : String) -> String {
  "file:" + rel
}

///|
pub(all) enum DocKind {
  StudioDoc
  FileDoc
} derive(Eq)

///|
pub extend DocKind with Eq::{not_equal, equal}

///|
pub(all) struct Document {
  id : String
  title : String
  resource : String
  kind : DocKind
  closable : Bool
}

///|
pub(all) struct TextBuffer {
  saved : String
  draft : String
  caret : Int32
  selection : @core.TextRange?
  md_session : @moui_richtext.MarkdownDocumentSession?
}

///|
pub(all) enum DocumentBody {
  TextBody(TextBuffer)
  VirtualBody
}

///|
pub(all) struct DocumentEntry {
  doc : Document
  body : DocumentBody
}

///|
pub(all) struct DocumentStore {
  entries : Array[DocumentEntry]
  active : Int32
}

///|
pub fn studio_document() -> Document {
  {
    id: STUDIO_DOC_ID,
    title: "Studio",
    resource: "",
    kind: StudioDoc,
    closable: false,
  }
}

///|
pub fn file_document(rel : String, title : String) -> Document {
  {
    id: file_document_id(rel),
    title,
    resource: rel,
    kind: FileDoc,
    closable: true,
  }
}

///|
pub fn DocumentStore::new() -> DocumentStore {
  { entries: [{ doc: studio_document(), body: VirtualBody, }], active: 0, }
}

///|
pub fn TextBuffer::new(rel : String, content : String) -> TextBuffer {
  {
    saved: content,
    draft: content,
    caret: 0,
    selection: None,
    md_session: if rel.has_suffix(".md") {
      Some(@moui_richtext.MarkdownDocumentSession::new(content))
    } else {
      None
    },
  }
}

///|
pub fn TextBuffer::is_dirty(self : TextBuffer) -> Bool {
  self.saved != self.draft
}

///|
pub fn DocumentEntry::text_buffer(self : DocumentEntry) -> TextBuffer? {
  match self.body {
    TextBody(buffer) => Some(buffer)
    VirtualBody => None
  }
}

///|
pub fn DocumentEntry::is_dirty(self : DocumentEntry) -> Bool {
  match self.body {
    TextBody(buffer) => buffer.is_dirty()
    VirtualBody => false
  }
}

///|
pub fn DocumentStore::find(self : DocumentStore, id : String) -> Int32 {
  let mut found = -1
  for i, entry in self.entries {
    if entry.doc.id == id {
      found = i
    }
  }
  found
}

///|
pub fn DocumentStore::find_file(self : DocumentStore, rel : String) -> Int32 {
  let mut found = -1
  for i, entry in self.entries {
    if entry.doc.kind is FileDoc && entry.doc.resource == rel {
      found = i
    }
  }
  found
}

///|
pub fn DocumentStore::entry(
  self : DocumentStore,
  id : String,
) -> DocumentEntry? {
  let index = self.find(id)
  if index < 0 {
    None
  } else {
    Some(self.entries[index])
  }
}

///|
pub fn DocumentStore::file_entries(
  self : DocumentStore,
) -> Array[DocumentEntry] {
  let files : Array[DocumentEntry] = []
  for entry in self.entries {
    if entry.doc.kind is FileDoc {
      files.push(entry)
    }
  }
  files
}

///|
/// 活动文档是可编辑文件时返回文档与正文；Studio 文档无正文，返回 None。
pub fn DocumentStore::active_file(
  self : DocumentStore,
) -> (Document, TextBuffer)? {
  match self.active_entry() {
    Some(entry) =>
      match (entry.doc.kind, entry.text_buffer()) {
        (FileDoc, Some(buffer)) => Some((entry.doc, buffer))
        _ => None
      }
    None => None
  }
}

///|
pub fn DocumentStore::active_entry(self : DocumentStore) -> DocumentEntry? {
  if self.active >= 0 && self.active < self.entries.length() {
    Some(self.entries[self.active])
  } else {
    None
  }
}

///|
pub fn DocumentStore::activate(
  self : DocumentStore,
  id : String,
) -> DocumentStore {
  let index = self.find(id)
  if index < 0 {
    self
  } else {
    { ..self, active: index, }
  }
}

///|
/// 同 id 原位替换（重新读取 = 刷新内容）并激活；新文档追加并激活。
pub fn DocumentStore::upsert_file(
  self : DocumentStore,
  doc : Document,
  buffer : TextBuffer,
) -> (DocumentStore, Int32) {
  let index = self.find(doc.id)
  let entry = { doc, body: TextBody(buffer), }
  if index >= 0 {
    let entries : Array[DocumentEntry] = []
    for i, item in self.entries {
      if i == index {
        entries.push(entry)
      } else {
        entries.push(item)
      }
    }
    ({ entries, active: index, }, index)
  } else {
    let entries = self.entries.copy()
    entries.push(entry)
    ({ entries, active: entries.length() - 1, }, entries.length() - 1)
  }
}

///|
/// 关闭文档并收敛活动下标：关闭活动文档时优先停在后一个 tab，末尾回退。
/// 常驻文档拒绝关闭。
pub fn DocumentStore::close(self : DocumentStore, id : String) -> DocumentStore {
  let index = self.find(id)
  if index < 0 || !self.entries[index].doc.closable {
    return self
  }
  let entries : Array[DocumentEntry] = []
  for i, entry in self.entries {
    if i != index {
      entries.push(entry)
    }
  }
  let active = if index < self.active {
    self.active - 1
  } else if index == self.active {
    if index < entries.length() {
      index
    } else {
      entries.length() - 1
    }
  } else {
    self.active
  }
  { entries, active, }
}

///|
fn DocumentStore::update_text(
  self : DocumentStore,
  id : String,
  update : (TextBuffer) -> TextBuffer,
) -> DocumentStore {
  let index = self.find(id)
  if index < 0 {
    return self
  }
  let entry = self.entries[index]
  match entry.body {
    VirtualBody => self
    TextBody(buffer) => {
      let next_entry = { ..entry, body: TextBody(update(buffer)), }
      let entries : Array[DocumentEntry] = []
      for i, item in self.entries {
        if i == index {
          entries.push(next_entry)
        } else {
          entries.push(item)
        }
      }
      { ..self, entries, }
    }
  }
}

///|
pub fn DocumentStore::edit(
  self : DocumentStore,
  id : String,
  value : String,
) -> DocumentStore {
  self.update_text(id, buffer => { ..buffer, draft: value, })
}

///|
pub fn DocumentStore::move_caret(
  self : DocumentStore,
  id : String,
  caret : Int32,
  selection : @core.TextRange?,
) -> DocumentStore {
  self.update_text(id, buffer => { ..buffer, caret, selection, })
}

///|
pub fn DocumentStore::apply_markdown_transaction(
  self : DocumentStore,
  id : String,
  transaction : @moui_richtext.MarkdownEditTransaction,
) -> DocumentStore {
  self.update_text(id, buffer => {
    let session = match buffer.md_session {
      Some(session) => session.apply(transaction)
      None => @moui_richtext.MarkdownDocumentSession::new(transaction.source)
    }
    {
      ..buffer,
      draft: transaction.source,
      caret: transaction.caret,
      selection: transaction.selection,
      md_session: Some(session),
    }
  })
}

///|
pub fn DocumentStore::rename_file(
  self : DocumentStore,
  rel : String,
  new_rel : String,
  new_title : String,
) -> DocumentStore {
  let entries : Array[DocumentEntry] = []
  for entry in self.entries {
    if entry.doc.kind is FileDoc && entry.doc.resource == rel {
      entries.push({
        ..entry,
        doc: {
          ..entry.doc,
          id: file_document_id(new_rel),
          resource: new_rel,
          title: new_title,
        },
      })
    } else {
      entries.push(entry)
    }
  }
  { ..self, entries, }
}

///|
pub fn DocumentStore::any_file_dirty(self : DocumentStore) -> Bool {
  for entry in self.entries {
    if entry.doc.kind is FileDoc && entry.is_dirty() {
      return true
    }
  }
  false
}

///|
/// 脏文件（资源路径, 草稿），供"保存全部"逐项落盘。
pub fn DocumentStore::dirty_files(
  self : DocumentStore,
) -> Array[(String, String)] {
  let dirty : Array[(String, String)] = []
  for entry in self.entries {
    if entry.doc.kind is FileDoc && entry.is_dirty() {
      match entry.text_buffer() {
        Some(buffer) => dirty.push((entry.doc.resource, buffer.draft))
        None => ()
      }
    }
  }
  dirty
}

///|
/// 保存回执：按资源定位文件，把落盘基准对齐当前草稿。
pub fn DocumentStore::mark_saved(
  self : DocumentStore,
  rel : String,
) -> DocumentStore {
  let index = self.find_file(rel)
  if index < 0 {
    return self
  }
  let id = self.entries[index].doc.id
  self.update_text(id, buffer => { ..buffer, saved: buffer.draft, })
}

///|
pub fn DocumentStore::close_file(
  self : DocumentStore,
  rel : String,
) -> DocumentStore {
  let index = self.find_file(rel)
  if index < 0 {
    self
  } else {
    self.close(self.entries[index].doc.id)
  }
}
