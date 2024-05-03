using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
namespace WindowsFormsApp1
{
    public class Masters
    {
        public Master[] masters;
    }
    public class Master
    {
        public string master_name { get; set; }
        public string shown_master_name { get; set; }
        public string header_img { get; set; }
        public string master_card_img { get; set; }
        public string command_spell_img { get; set; }
        public Effect[] effects { get; set; }
        public Specials specials { get; set; }
        public Upgrade_Skill[] upgrade_skill { get; set; }
    }

    public class Specials
    {
        public SKILL[] SKILLS { get; set; }
        public ATTACK[] ATTACKS { get; set; }
    }

    public class SKILL
    {
        public string skill_name { get; set; }
        public string skill_card_img { get; set; }
        public Effect[] effects { get; set; }
    }

    public class Effect
    {
        public string effect_name { get; set; }
        public string[] time_points { get; set; }
        public Func[] funcs { get; set; }
    }

    public class ATTACK
    {
        public string attack_name { get; set; }
        public string attack_crad_img { get; set; }
        public Effect[] effects { get; set; }
    }


    public class Func
    {
        public string func_name { get; set; }
        public int[] parameters { get; set; }
    }

    public class Upgrade_Skill
    {
        public string skill_name { get; set; }
        public string skill_card_img { get; set; }
        public Effect[] effects { get; set; }
    }



}

