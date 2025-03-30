{...}:{
  services.fs-watcher = {
    enable = true;
    directories = {
      "/home/hannses/tmp" = {
        match.include = "*.typ";
        command = "typst c $3";
      };
    };
    user = "hannses";
  };
}
