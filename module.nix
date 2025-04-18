{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.fs-watcher;
  inherit (lib)
    mkEnableOption
    mkOption
    mapAttrs'
    head
    replaceStrings
    listToAttrs
    filterAttrs
    concatStringsSep
    optionalString
    attrNames
    ;
  inherit (lib.types)
    attrsOf
    submodule
    str
    either
    package
    passwdEntry
    nullOr
    bool
    ;
  userNameType = passwdEntry str;
  mapListToAttrs = f: list: listToAttrs (map f list);
in
{
  options.services.fs-watcher = {
    enable = mkEnableOption ''Wether to enable the fs-watcher'';
    user = mkOption {
      type = userNameType;
      description = ''The username under which to run the services by default'';
    };
    recursive = mkOption {
      type = bool;
      description = ''Wether to watch the directories recursively'';
      default = true;
    };
    directories = mkOption {
      type = attrsOf (
        submodule (
          { name, ... }:
          let
            innerCfg = cfg.directories.${name};
            regexOpt =
              description:
              mkOption {
                type = nullOr str;
                default = null;
                description = "${description} matching the extended regular expression";
              };
          in
          {
            options = {
              recursive = mkOption {
                type = bool;
                description = ''Wether to watch the directory recursively'';
                default = cfg.recursive;
              };
              match = {
                exclude = regexOpt "Exclude all events on files";
                excludei = regexOpt "like exclude but case insensitive";
                include = regexOpt "Exclude all events on files except the ones";
                includei = regexOpt "Like --include but case insensitive";
              };
              command = mkOption {
                type = str;
                example = "typst c $1";
                description = ''
                  command to execute on all files matched by regex
                '';
              };
              user = mkOption {
                type = userNameType;
                description = ''
                  the username under which to run the service for this dir.
                  defaults to the one declared at the service level
                '';
                default = cfg.user;
              };
              ifOutputOlder = mkOption {
                type = nullOr str;
                description = ''
                  provide a path to a executable that when called outputs the path of the file that would be created
                  if provided use make to guarantee the
                  the output file is only updated if the input is newer
                '';
                default = null;
              };
              notifications =
                mapListToAttrs
                  (set: {

                    inherit (set) name;
                    value = {
                      enable = mkOption {
                        type = bool;
                        inherit (set) default;
                        description = ''
                          wether to watch for changes of kind:
                          ${set.description}
                        '';
                      };
                      command = mkOption {
                        type = str;
                        default = innerCfg.command;
                        description = ''
                          The command to execute on change:
                          ${set.description}
                          Defaults to the one defined one level above
                        '';
                      };

                    };
                  })
                  [
                    {
                      name = "access";
                      description = "file or directory contents were read";
                      default = false;
                    }
                    {
                      name = "modify";
                      description = "file or directory contents were written";
                      default = true;
                    }
                    {
                      name = "attrib";
                      description = "file or directory attributes changed";
                      default = false;
                    }
                    {
                      name = "close_write";
                      description = "file or directory closed, after being opened in writable mode";
                      default = true;
                    }
                    {
                      name = "close_nowrite";
                      description = "file or directory closed, after being opened in read-only mode";
                      default = false;
                    }
                    {
                      name = "close";
                      description = "file or directory closed, regardless of read/write mode";
                      default = false;
                    }
                    {
                      name = "open";
                      description = "file or directory opened";
                      default = false;
                    }
                    {
                      name = "moved_to";
                      description = "file or directory moved to watched directory";
                      default = true;
                    }
                    {
                      name = "moved_from";
                      description = "file or directory moved from watched directory";
                      default = false;
                    }
                    {
                      name = "move";
                      description = "file or directory moved to or from watched directory ";
                      default = false;
                    }
                    {
                      name = "move_self";
                      description = "A watched file or directory was moved.";
                      default = false;
                    }
                    {
                      name = "create";
                      description = "file or directory created within watched directory";
                      default = true;
                    }
                    {
                      name = "delete";
                      description = "file or directory deleted within watched directory";
                      default = false;
                    }
                    {
                      name = "delete_self";
                      description = "file or directory was deleted";
                      default = false;
                    }
                    {
                      name = "unmount";
                      description = "file system containing file or directory unmounted";
                      default = false;
                    }
                  ];
            };
          }
        )
      );
    };
  };
  config =
    let
      commandScript =
        {
          command,
          notifications,
          ifOutputOlder,
          match,
          folderName,
          name,
          ...
        }:
        let
          eventsOpts = map (name: "-e ${name}") (attrNames (filterAttrs (_: set: set.enable) notifications));
          cut = col: ''$(echo -ne "$REPLY" | cut -d $'\0' -f ${toString col})'';
          commandFmt = "${command} $dir $file $dir_file $time";
          finalCommand =
            if ifOutputOlder != null then
              ''
                output_name=$(${ifOutputOlder} $dir $file $dir_file $time)
                tmpdir=$(mktemp -d)
                echo "$output_name: $dir_file" >> $tmpdir/Makefile
                echo "    ${command} "$dir" "$file" "$dir" "$dif_file" "$time"" >> $tmpdir/Makefile
                ${pkgs.gnumake} -f $tmpdir/Makefile $output_name
                echo "Makefile created in $tmpdir"
                #rm -rf $tmpdir
              ''
            else
              commandFmt;
        in
        pkgs.writeShellScript name ''
          echo "file updated: $1" > "/tmp/fs-watcher-logs"
          ${pkgs.inotify-tools}/bin/inotifywait ${folderName} -m ${concatStringsSep " " eventsOpts} ${
            optionalString (match.include != null) "--include ${match.include}"
          } ${optionalString (match.includei != null) "--includei ${match.includei}"} ${
            optionalString (match.exclude != null) "--exclude ${match.exclude}"
          } ${
            optionalString (match.excludei != null) "--excludei ${match.excludei}"
          } --format '%w%0%f%0%w%f%0%e%0%T' --timefmt "%F %T %s" | while IFS= read; do
            echo "$REPLY" > /tmp/fs-watcher-logs
            export dir=${cut 2}
            export file=${cut 3}
            export dir_file=${cut 4}
            export event=${cut 5}
            export time=${cut 6}
            pushd $dir
              ${finalCommand}
            popd
            done
        '';
    in
    {
      systemd.services = lib.mkIf cfg.enable (
        mapAttrs' (
          folderName: value:
          let
            name = "watcher-${replaceStrings [ "/" ] [ "-" ] folderName}";
          in
          {
            inherit name;
            value = {
              wantedBy = [ "multi-user.target" ];
              after = [ "local-fs.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart = "${commandScript (value // { inherit folderName name; })}";
                RemainAfterExit = "no";
                User = value.user;
              };
            };
          }
        ) cfg.directories
      );
    };
}
