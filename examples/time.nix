{

  yo.scripts.time = {
    description = "Tells time, day, date & week";
    category = "Miscellaneous";
    code = ''
      export LC_TIME=en_US.UTF-8
      TIME=$(date "+%H . %M")
      DAY=$(date "+%A")
      DATE=$(date "+%d %B")
      WEEK=$(date +%V)
      echo "The time is $TIME. It is $DAY, $DATE. Week $WEEK" 
      yo say "The time is $TIME. It is $DAY, $DATE. Week $WEEK"
    '';
    voice = {
      enabled = true;
      priority = 2;
      sentences = [
        "(what|whats) the time"
        "what (time|day|week|date) is it [now|today]"
      ];
    };
    
  };}
