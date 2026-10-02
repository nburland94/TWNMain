const fs = require('fs'), vm = require('vm'), assert = require('assert');
const template = fs.readFileSync('Resources/premiere/sort-import.jsx','utf8');
function item(name){const i={name,label:-1,children:[],setColorLabel(n){this.label=n},getColorLabel(){return this.label},createBin(name){const child=item(name);this.children.push(child);return child}};Object.defineProperty(i.children,'numItems',{get(){return this.length}});return i}
const root=item('project'),messages=[];
const data={name:'A "quote" & scene',scenes:[{name:'SCENE_01',label:0,clips:[{kind:'video',path:'video/test.mxf'},{kind:'audio',path:'audio/test.wav'}]},{name:'SCENE_02',label:9,clips:[{kind:'video',path:'video/blue.mov'}]}]};
const ctx={app:{project:{rootItem:root,importFiles(paths,quiet,bin){bin.children.push(item(paths[0]));return true}}},File:function(path){this.parent={fsName:'/tmp/sorted'};this.fsName=path;this.exists=true},$:{fileName:'/tmp/sorted/_IMPORT_IN_PREMIERE.jsx'},confirm(){return true},alert(s){messages.push(s)}};
vm.runInNewContext(template.replace('__NEEDED_SORT_DATA__',JSON.stringify(data)),ctx);
assert.equal(root.children[0].children.length,2);
for (const scene of root.children[0].children){assert([0,9].includes(scene.label));for(const group of scene.children)for(const clip of group.children)assert.equal(clip.label,scene.label)}
assert(messages[0].startsWith('Imported 3 items.'));
console.log('PASS: separate scene/media bins, clip colour API calls, quoted names');
