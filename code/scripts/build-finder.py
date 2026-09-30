#!/usr/bin/env python3
"""Build the self-contained Finder Quick Action; does not install it."""
import pathlib
import plistlib
import uuid

root = pathlib.Path(__file__).resolve().parent.parent
bundle = root / 'build' / 'New Markdown File.workflow'
resources = bundle / 'Contents' / 'Resources'
resources.mkdir(parents=True, exist_ok=True)


def action(name, params):
    path = pathlib.Path('/System/Library/Automator') / (name + '.action')
    info = plistlib.loads((path / 'Contents' / 'Info.plist').read_bytes())
    payload = {
        'ActionBundlePath': str(path),
        'ActionName': name,
        'ActionParameters': params,
        'AMAccepts': info['AMAccepts'],
        'AMProvides': info['AMProvides'],
        'AMActionVersion': info['CFBundleShortVersionString'],
        'Application': [info['AMApplication']],
        'UnlocalizedApplications': [info['AMApplication']],
        'BundleIdentifier': info['CFBundleIdentifier'],
        'Class Name': info['NSPrincipalClass'],
        'CFBundleVersion': info['CFBundleVersion'],
        'Category': info['AMCategory'],
        'CanShowSelectedItemsWhenRun': False,
        'CanShowWhenRun': False,
        'InputUUID': str(uuid.uuid4()).upper(),
        'OutputUUID': str(uuid.uuid4()).upper(),
        'UUID': str(uuid.uuid4()).upper(),
        'arguments': {},
        'AMParameterProperties': {},
        'isViewVisible': True,
    }
    return {'action': payload, 'isViewVisible': True}


workflow = {
    'AMApplicationBuild': '523',
    'AMApplicationVersion': '2.10',
    'AMDocumentVersion': '2',
    'actions': [
        action('Run Shell Script', {
            'CheckedForUserDefaultShell': True,
            'COMMAND_STRING': (root / 'src' / 'new-file.zsh').read_text(),
            'inputMethod': 1,
            'shell': '/bin/zsh',
            'source': '',
        }),
        action('Reveal Finder Items', {}),
    ],
    'connectors': {},
    'workflowMetaData': {
        'serviceApplicationBundleID': 'com.apple.finder',
        'serviceApplicationPath': '/System/Library/CoreServices/Finder.app',
        'serviceInputTypeIdentifier': 'com.apple.Automator.fileSystemObject',
        'serviceOutputTypeIdentifier': 'com.apple.Automator.nothing',
        'serviceProcessesInput': 0,
        'workflowTypeIdentifier': 'com.apple.Automator.servicesMenu',
    },
}
info = {
    'CFBundleIdentifier': 'local.mdrift.new-file',
    'CFBundleName': 'New Markdown File',
    'CFBundleShortVersionString': '1.0',
    'NSServices': [{
        'NSMenuItem': {'default': 'New Markdown File'},
        'NSMessage': 'runWorkflowAsService',
        'NSRequiredContext': {'NSApplicationIdentifier': 'com.apple.finder'},
        'NSSendFileTypes': ['public.item'],
    }],
}
(resources / 'document.wflow').write_bytes(plistlib.dumps(workflow, sort_keys=False))
(bundle / 'Contents' / 'Info.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
print(bundle)
