module.exports = function (grunt) {
    var fs = require('fs');
    var path = require('path');

    var pkg = grunt.file.readJSON('package.json');
    var currentPath = path.dirname(fs.realpathSync(__filename));

    grunt.initConfig({
        pkg: pkg,

        mkdir: {
            tmp: {
                options: {
                    mode: 0755,
                    create: [
                        'build/tmp',
                    ]
                },

            }
        },
        clean: {
            start: ['build/installer-*'],
            final: [
                'build/tmp',
                'build/installer-' + pkg.version + '/' + pkg.name + '-' + pkg.version
            ]
        },
        copy: {
            options: {
                mode: true,
            },
            files: {
                expand: true,
                dot: true,
                src: [
                    'commands/**',
                    'installation-modes/**',
                    'system-configuration/**',
                    'LICENSE'
                ],
                dest: 'build/tmp/<%= pkg.name %>-<%= pkg.version %>/',
            },
            script: {
                expand: true,
                dot: true,
                src: [
                    'install.sh'
                ],
                dest: 'build/tmp/',
            },
            final: {
                expand: true,
                dot: true,
                src: '**',
                cwd: 'build/tmp',
                dest: 'build/installer-<%= pkg.version %>/',
            },
        },
        replace: {
            version: {
                options: {
                    patterns: [
                        {
                            match: /archive\/refs\/heads\/master/g,
                            replacement: 'releases/download/<%= pkg.version %>/<%= pkg.name %>-<%= pkg.version %>'
                        },
                        {
                            match: /installer MASTER/g,
                            replacement: 'installer v<%= pkg.version %>'
                        },
                        {
                            match: /espocrm-installer-master/g,
                            replacement: 'espocrm-installer-<%= pkg.version %>'
                        },
                        {
                            match: /2014-20[0-9][0-9] Yu/g,
                            replacement: '2014-<%= grunt.template.today("yyyy") %> Yu'
                        }
                    ]
                },
                files: [
                    {
                        src: 'build/tmp/install.sh',
                        dest: 'build/tmp/install.sh'
                    },
                    {
                        src: 'build/tmp/<%= pkg.name %>-<%= pkg.version %>/commands/command.sh',
                        dest: 'build/tmp/<%= pkg.name %>-<%= pkg.version %>/commands/command.sh'
                    }
                ]
            }
        },
    });

    grunt.registerTask("zip", function() {
        var resolve = this.async();

        var folder = pkg.name + '-' + pkg.version;

        var zipPath = 'build/installer-' + pkg.version + '/' + folder +'.zip';
        if (fs.existsSync(zipPath)) fs.unlinkSync(zipPath);

        var archiver = require('archiver');
        var archive = archiver('zip');

        archive.on('error', function (err) {
            grunt.fail.warn(err);
        });
        var zipOutput = fs.createWriteStream(zipPath);
        zipOutput.on('close', function () {
            console.log("Package has been built.");
            resolve();
        });

        archive.directory(currentPath + '/build/installer-' + pkg.version + '/' + folder, folder).pipe(zipOutput);

        archive.finalize();
    });

    grunt.loadNpmTasks('grunt-contrib-clean');
    grunt.loadNpmTasks('grunt-mkdir');
    grunt.loadNpmTasks('grunt-contrib-copy');
    grunt.loadNpmTasks('grunt-replace');

    grunt.registerTask('default', [
        'clean:start',
        'mkdir:tmp',
        'copy:files',
        'copy:script',
        'replace',
        'copy:final',
        'zip',
        'clean:final',
    ]);
};
