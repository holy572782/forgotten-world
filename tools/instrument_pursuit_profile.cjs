// Install query counters only in the isolated validation project.
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const copy = path.join(root, '.godot', 'mage_fire_validation');
const files = ['combat/terrain_ground', 'combat/melee_terrain', 'combat/elevation_path',
  'combat/dash_path', 'combat/jump_arc', 'enemies/enemy_walk',
  'enemies/practice_enemy', 'enemies/enemy_pursuit_route'];
const args = process.argv.slice(2);
const revision = args.includes('--revision') ? args[args.indexOf('--revision')+1] : null;
for (const name of files) {
  const relative = `scripts/${name}.gd`;
  let source = (revision ? execFileSync('git', ['show', `${revision}:${relative}`], {cwd:root,encoding:'utf8'}) : fs.readFileSync(path.join(root, relative), 'utf8')).replace(/^\uFEFF/, '');
  if (args.includes('--clean')) {
    fs.writeFileSync(path.join(copy, relative), source);
    continue;
  }
  source = source.replace(/^(extends (?:RefCounted|CharacterBody3D))/, '$1\nconst Probe=preload("res://tests/fixtures/pursuit_query_probe.gd")');
  source = source.replace(/\b(body|actor)\.test_move\(/g, 'Probe.motion($1,');
  for (const [method, wrapper] of [['intersect_ray','ray'],['intersect_shape','shape'],['cast_motion','cast'],['collide_shape','contacts']]) {
    source = source.replace(new RegExp('((?:body|actor)\\.get_world_3d\\(\\)\\.direct_space_state|space)\\.'+method+'\\(', 'g'), `Probe.${wrapper}($1,`);
  }
  source = source.replace('var result:=Elevation.attack(', 'var result:=Probe.attack(Elevation,');
  source = source.replace(/(func _attack_position_available\(\) -> bool:\r?\n)/, '$1\tProbe.hit("availability_calls")\n');
  source = source.replace('waypoints=_find(actor,safe_goal)', 'waypoints=Probe.find(self,actor,safe_goal)');
  source = source.replaceAll('\t_advance_search(actor)', '\tProbe.advance(self,actor)');
  source = source.replace(/(func _begin_search\(actor: CharacterBody3D, goal_at: Vector3\) -> void:\r?\n)/, '$1\tProbe.hit("searches")\n');
  fs.writeFileSync(path.join(copy, relative), source);
}
console.log(args.includes('--clean') ? 'Validation copy restored without counters' : 'Profiling copy instrumented; production sources unchanged');
