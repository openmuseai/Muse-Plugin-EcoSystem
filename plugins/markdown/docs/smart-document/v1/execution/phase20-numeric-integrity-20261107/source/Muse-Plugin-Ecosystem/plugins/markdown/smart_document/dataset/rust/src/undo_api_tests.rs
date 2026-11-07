//! Contract coverage for the optional bounded entry points. The original
//! default API deliberately retains its original skip-to-applicable behavior.
use collab::preclude::{Doc, Map, Transact, UndoManager};
#[test]
fn optional_single_pop_preserves_old_default_and_does_not_touch_an_earlier_command() {
    for bounded in [false, true] {
        let doc = Doc::with_client_id(42);
        let map = doc.get_or_insert_map("history");
        let mut history = UndoManager::new(&doc, &map);
        history.include_origin("local");
        map.insert(&mut doc.transact_mut_with("local"), "earlier", "keep");
        history.reset();
        map.insert(&mut doc.transact_mut_with("local"), "shared", "local");
        history.reset();
        map.insert(&mut doc.transact_mut_with("peer"), "shared", "peer");
        assert_eq!(history.undo_stack().len(), 2);
        let changed = if bounded {
            history.undo_one_blocking()
        } else {
            history.undo_blocking()
        };
        assert_eq!(changed, !bounded);
        assert_eq!(history.undo_stack().len(), usize::from(bounded));
        assert_eq!(map.get(&doc.transact(), "earlier").is_some(), bounded);
        assert_eq!(
            map.get(&doc.transact(), "shared")
                .unwrap()
                .to_string(&doc.transact()),
            "peer"
        );
        if bounded {
            assert!(history.undo_one_blocking());
            assert!(map.get(&doc.transact(), "earlier").is_none());
        }
    }
}
#[test]
fn bounded_redo_processes_only_one_captured_command_at_a_time() {
    let doc = Doc::with_client_id(42);
    let map = doc.get_or_insert_map("history");
    let mut history = UndoManager::new(&doc, &map);
    map.insert(&mut doc.transact_mut(), "one", "1");
    history.reset();
    map.insert(&mut doc.transact_mut(), "two", "2");
    history.reset();
    assert!(history.undo_one_blocking());
    assert!(history.undo_one_blocking());
    assert_eq!(history.redo_stack().len(), 2);
    assert!(history.redo_one_blocking());
    assert!(map.get(&doc.transact(), "one").is_some());
    assert!(map.get(&doc.transact(), "two").is_none());
    assert_eq!(history.redo_stack().len(), 1);
    assert!(history.redo_one_blocking());
    assert!(map.get(&doc.transact(), "two").is_some());
}
