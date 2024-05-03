using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WindowsFormsApp1
{
    internal class Util
    {
        public void Write_Json(string str)
        {
            //path should be modified
            File.WriteAllText(Directory.GetCurrentDirectory() + "\\test1.json", str, System.Text.Encoding.UTF8);
        }
        public string Read_Json()
        {
            //path should be modified
            string str = File.ReadAllText(Directory.GetCurrentDirectory() + "\\test.json");
            return str;
        }

        public class JSON_util
        {
            public Masters JSON_to_Master(string jsonstr)
            {
                Masters m = Newtonsoft.Json.JsonConvert.DeserializeObject<Masters>(jsonstr);
                return m;
            }
            public string Masters_to_JSON(Masters m)
            {
                string json = Newtonsoft.Json.JsonConvert.SerializeObject(m);
                return json;
            }
        }
    }
}
