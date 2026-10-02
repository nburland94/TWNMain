// Run in Premiere using an ExtendScript-capable script runner.
// Uses Adobe's projectItem.setColorLabel API; does not modify existing timelines.
(function () {
    if (!app.project || !app.project.rootItem) { alert('Open a Premiere project first.'); return; }
    var data = __NEEDED_SORT_DATA__;
    if (!confirm('Import ' + data.scenes.length + ' sorted scenes into a new Needed Sort bin?')) return;
    var root = app.project.rootItem.createBin(data.name + ' — Needed Sort');
    if (!root) { alert('Could not create the import bin.'); return; }
    var base = new File($.fileName).parent.fsName;
    var errors = [], imported = 0;
    function label(item, colour) {
        if (colour < 0) return;
        item.setColorLabel(colour);
        if (item.getColorLabel() !== colour) throw new Error('Premiere did not accept the colour label');
    }
    for (var i = 0; i < data.scenes.length; i++) {
        var scene = data.scenes[i], bin = root.createBin(scene.name);
        try { label(bin, scene.label); } catch (e) { errors.push(scene.name + ': ' + e); }
        for (var k = 0; k < 2; k++) {
            var kind = k === 0 ? 'video' : 'audio', group = null;
            for (var n = 0; n < scene.clips.length; n++) {
                var clip = scene.clips[n]; if (clip.kind !== kind) continue;
                try {
                    if (!group) { group = bin.createBin(k === 0 ? 'Video' : 'Audio'); label(group, scene.label); }
                    var file = new File(base + '/' + clip.path);
                    if (!file.exists) throw new Error('File is missing');
                    var before = group.children.numItems;
                    if (!app.project.importFiles([file.fsName], true, group, false)) throw new Error('Import failed');
                    if (group.children.numItems <= before) throw new Error('No imported clip returned');
                    for (var c = before; c < group.children.numItems; c++) { label(group.children[c], scene.label); imported++; }
                } catch (e) { errors.push(clip.path + ': ' + e); }
            }
        }
    }
    alert('Imported ' + imported + ' items.' + (errors.length ? '\nNeeds attention:\n' + errors.join('\n') : '\nAdd these labelled clips to your timeline.'));
}());
