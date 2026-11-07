import 'dart:convert';import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
class Memory implements DocumentStore {Future<Map<String,dynamic>?> read()async=>null;Future<void> write(Map<String,dynamic> v)async{}}
void main(){TestWidgetsFlutterBinding.ensureInitialized();HttpOverrides.global=null;
test('read current isolated Cloud diagnostic',()async{
 final root=Directory('../../.build');final config=jsonDecode(await File('${root.path}/outline-web-public.json').readAsString()) as Map;
 final f=jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString()) as Map;
 final c=await SmartDocumentController.open(core:NativeDocumentCore(),store:Memory(),objectId:config['OUTLINE_OBJECT'] as String,editable:false,syncInterval:null,
 provider:AppFlowyCollaborationProvider(origin:Uri.parse(config['SMARTDOC_ORIGIN'] as String),workspaceId:config['SMARTDOC_WORKSPACE'] as String,deviceId:'outline-diag',accessToken:()async=>f['users']['bob']['accessToken'] as String));
 await File('${root.path}/p19-live-cloud-diagnostic.json').writeAsString(jsonEncode({'outline':c.snapshot['outline'],'stateVector':c.snapshot['stateVector'],'data':c.snapshot['data']}));
 for(final actor in ['alice','bob','bob-after-rename']) {
  final file=File('${root.path}/p19-live-browser-$actor.json');
  if(await file.exists()){
   final snapshot=jsonDecode(await file.readAsString()) as Map;
   final peer=await SmartDocumentController.open(core:NativeDocumentCore(),store:Memory(),objectId:config['OUTLINE_OBJECT'] as String,editable:false,syncInterval:null,initialDocState:snapshot['docState'] as String);
   await File('${root.path}/p19-browser-native-$actor.json').writeAsString(jsonEncode({'outline':peer.snapshot['outline'],'stateVector':peer.snapshot['stateVector'],'matchesBrowser':jsonEncode(peer.snapshot['outline'])==jsonEncode(snapshot['outline'])}));await peer.close();
  }
 }
 await c.close();
});}
